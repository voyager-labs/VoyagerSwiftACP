package property

import (
	"context"
	"errors"
	"math/big"
	"regexp"
	"sort"
	"strings"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/source"
)

const maximumQueryValueMembers = 16384

var (
	ErrInvalidConditionQuery       = errors.New("invalid property condition query")
	ErrConditionQueryScopeTooLarge = errors.New("property condition query scope too large")
)

type ConditionCapability struct {
	Supported        bool
	NativeType       domainentry.ConditionNativeType
	AllowedOperators []string
	Reason           string
}

// ConditionCapabilityFor derives query support only from the immutable value
// contract. It is deliberately unrelated to mutation/editability capability.
func ConditionCapabilityFor(definition domainentry.WorkspacePropertyDefinition) ConditionCapability {
	if definition.Lifecycle != domainentry.PropertyLifecycleActive {
		return ConditionCapability{Reason: "definition_disabled"}
	}
	if definition.Origin == domainentry.PropertyOriginBuiltIn {
		return ConditionCapability{Reason: "source_runtime_unavailable"}
	}
	nativeType, ok := domainentry.ConditionNativeTypeForContract(definition.ValueType, definition.Cardinality)
	if !ok {
		return ConditionCapability{Reason: "unsupported_value_contract"}
	}
	operators := append([]string(nil), domainentry.ConditionCatalogData.OperatorsForType(nativeType)...)
	sort.Strings(operators)
	return ConditionCapability{Supported: true, NativeType: nativeType, AllowedOperators: operators}
}

type ConditionOperand struct {
	Kind    string
	Values  []string
	Boolean *bool
}

type QueryCondition struct {
	PropertyID domainentry.PropertyID
	Operator   string
	Operand    ConditionOperand
}

type ConditionQuery struct {
	LocalPaths            []string
	Combinator            string
	Conditions            []QueryCondition
	ProjectionPropertyIDs []domainentry.PropertyID
	EvaluationDate        string
	PageSize              int
	CandidateOffset       int
}

type ConditionQueryItem struct {
	CandidateIndex int
	EntryID        string
	Projection     []domainentry.EntryPropertyAssignment
}

type ConditionQueryResult struct {
	Items                      []ConditionQueryItem
	UnresolvedCandidateIndices []int
	NextCandidateOffset        int
	HasMore                    bool
	Definitions                map[domainentry.PropertyID]DefinitionView
}

type ConditionQueryService struct {
	catalog CatalogRepository
	facts   AssignmentFactRepository
	targets LocalPathResolver
	runner  TransactionRunner
}

type conditionQueryMemberCappedRepository interface {
	LoadAssignmentsMemberCapped(ctx context.Context, workspace domainentry.WorkspaceContext, entryIDs []string, propertyIDs []domainentry.PropertyID, maxMembers int) ([]domainentry.EntryPropertyAssignment, error)
}

func NewConditionQueryService(catalog CatalogRepository, facts AssignmentFactRepository, targets LocalPathResolver, runner TransactionRunner) (*ConditionQueryService, error) {
	if catalog == nil || facts == nil || targets == nil || runner == nil {
		return nil, ErrInvalidConditionQuery
	}
	return &ConditionQueryService{catalog: catalog, facts: facts, targets: targets, runner: runner}, nil
}

func (service *ConditionQueryService) Query(ctx context.Context, workspace domainentry.WorkspaceContext, query ConditionQuery) (ConditionQueryResult, error) {
	if ValidateWorkspaceContext(workspace) != nil || query.CandidateOffset < 0 || query.CandidateOffset >= len(query.LocalPaths) ||
		(query.Combinator != "all" && query.Combinator != "any") || len(query.Conditions) < 1 || query.PageSize < 1 {
		return ConditionQueryResult{}, ErrInvalidConditionQuery
	}
	propertyIDs := queryPropertyIDs(query)
	if len(query.LocalPaths)*len(propertyIDs) > 4096 {
		return ConditionQueryResult{}, ErrConditionQueryScopeTooLarge
	}

	type resolvedCandidate struct {
		index   int
		entryID string
	}
	resolved := make([]resolvedCandidate, 0, len(query.LocalPaths)-query.CandidateOffset)
	unresolved := make([]int, 0)
	for index := query.CandidateOffset; index < len(query.LocalPaths); index++ {
		target, err := service.targets.ResolveLocalPath(ctx, query.LocalPaths[index])
		if err != nil {
			if errors.Is(err, source.ErrEntryNotFound) || errors.Is(err, source.ErrPermissionDenied) {
				unresolved = append(unresolved, index)
				continue
			}
			return ConditionQueryResult{}, err
		}
		if target.Validate() != nil {
			return ConditionQueryResult{}, ErrInvalidResolvedTarget
		}
		resolved = append(resolved, resolvedCandidate{index: index, entryID: target.EntryRef.EntryID})
	}
	entryIDs := make([]string, len(resolved))
	for index := range resolved {
		entryIDs[index] = resolved[index].entryID
	}
	var definitions map[domainentry.PropertyID]DefinitionView
	var facts []domainentry.EntryPropertyAssignment
	err := service.runner.WithinTx(ctx, func(txctx context.Context) error {
		rows, _, _, err := service.catalog.DefinitionsPage(txctx, workspace, false, propertyIDs, nil, len(propertyIDs))
		if err != nil {
			return err
		}
		options, err := service.catalog.OptionsForDefinitions(txctx, workspace, propertyIDs)
		if err != nil {
			return err
		}
		definitions = make(map[domainentry.PropertyID]DefinitionView, len(rows))
		for _, definition := range rows {
			definitions[definition.PropertyID] = DefinitionView{Definition: definition, Options: options[definition.PropertyID]}
		}
		if capped, ok := service.facts.(conditionQueryMemberCappedRepository); ok {
			facts, err = capped.LoadAssignmentsMemberCapped(txctx, workspace, entryIDs, propertyIDs, maximumQueryValueMembers)
		} else {
			facts, err = service.facts.LoadAssignments(txctx, workspace, entryIDs, propertyIDs)
		}
		return err
	})
	if err != nil {
		return ConditionQueryResult{}, err
	}
	members := 0
	indexedFacts := make(map[string]domainentry.EntryPropertyAssignment, len(facts))
	for _, fact := range facts {
		if fact.Scalar != nil {
			members++
		} else {
			members += len(fact.Many)
		}
		if members > maximumQueryValueMembers {
			return ConditionQueryResult{}, ErrConditionQueryScopeTooLarge
		}
		indexedFacts[fact.EntryID+"\x00"+fact.PropertyID.String()] = fact
	}
	result := ConditionQueryResult{Items: []ConditionQueryItem{}, UnresolvedCandidateIndices: []int{}, Definitions: definitions}
	for _, candidate := range resolved {
		matched := query.Combinator == "all"
		for _, condition := range query.Conditions {
			view, ok := definitions[condition.PropertyID]
			conditionMatched := false
			if ok {
				fact, found := indexedFacts[candidate.entryID+"\x00"+condition.PropertyID.String()]
				if !found {
					fact = domainentry.ImplicitUnsetEntryPropertyAssignment(workspace.ID, candidate.entryID, condition.PropertyID)
				}
				conditionMatched = evaluateCondition(view, fact, condition, query.EvaluationDate)
			}
			if query.Combinator == "all" && !conditionMatched {
				matched = false
				break
			}
			if query.Combinator == "any" && conditionMatched {
				matched = true
				break
			}
		}
		if !matched {
			continue
		}
		projection := make([]domainentry.EntryPropertyAssignment, 0, len(query.ProjectionPropertyIDs))
		for _, propertyID := range query.ProjectionPropertyIDs {
			if fact, ok := indexedFacts[candidate.entryID+"\x00"+propertyID.String()]; ok {
				projection = append(projection, fact)
			}
		}
		result.Items = append(result.Items, ConditionQueryItem{CandidateIndex: candidate.index, EntryID: candidate.entryID, Projection: projection})
		if len(result.Items) == query.PageSize {
			result.NextCandidateOffset = candidate.index + 1
			result.HasMore = result.NextCandidateOffset < len(query.LocalPaths)
			break
		}
	}
	end := len(query.LocalPaths)
	if result.HasMore {
		end = result.NextCandidateOffset
	}
	for _, index := range unresolved {
		if index < end {
			result.UnresolvedCandidateIndices = append(result.UnresolvedCandidateIndices, index)
		}
	}
	return result, nil
}

func queryPropertyIDs(query ConditionQuery) []domainentry.PropertyID {
	seen := make(map[domainentry.PropertyID]struct{}, len(query.Conditions)+len(query.ProjectionPropertyIDs))
	for _, condition := range query.Conditions {
		seen[condition.PropertyID] = struct{}{}
	}
	for _, id := range query.ProjectionPropertyIDs {
		seen[id] = struct{}{}
	}
	ids := make([]domainentry.PropertyID, 0, len(seen))
	for id := range seen {
		ids = append(ids, id)
	}
	sort.Slice(ids, func(i, j int) bool { return ids[i].String() < ids[j].String() })
	return ids
}

func evaluateCondition(view DefinitionView, fact domainentry.EntryPropertyAssignment, condition QueryCondition, evaluationDate string) bool {
	capability := ConditionCapabilityFor(view.Definition)
	if !capability.Supported || !containsString(capability.AllowedOperators, condition.Operator) {
		return false
	}
	operator, ok := domainentry.ConditionCatalogData.LookupOperator(condition.Operator)
	if !ok || condition.Operand.Kind != conditionOperandKind(operator.ValueShape, capability.NativeType) {
		return false
	}
	if condition.Operand.Kind == "option_ref" && !allOperandsAreActiveOptions(view.Options, condition.Operand.Values) {
		return false
	}
	if condition.Operator == "empty" {
		return assignmentEmpty(fact)
	}
	if condition.Operator == "exists" {
		return !assignmentEmpty(fact)
	}
	if fact.State != domainentry.AssignmentStateValue {
		return false
	}
	values := assignmentStrings(fact)
	switch condition.Operator {
	case "eq", "neq", "gt", "gte", "lt", "lte", "btw", "nbtw":
		return compareOrdered(values, condition, capability.NativeType)
	case "today":
		return len(values) == 1 && values[0] == evaluationDate && condition.Operand.Kind == "none"
	case "cn", "nc", "sw", "ew", "rx":
		return compareText(values, condition)
	case "all":
		return containsAll(values, condition.Operand.Values, capability.NativeType == domainentry.ConditionNativeTypeString)
	case "any":
		return containsAny(values, condition.Operand.Values, capability.NativeType == domainentry.ConditionNativeTypeString)
	case "none":
		return !containsAny(values, condition.Operand.Values, false)
	case "miss":
		return !containsAll(values, condition.Operand.Values, false)
	default:
		return false
	}
}

func conditionOperandKind(shape domainentry.ConditionValueShape, nativeType domainentry.ConditionNativeType) string {
	switch shape {
	case domainentry.ConditionValueShapeNone:
		return "none"
	case domainentry.ConditionValueShapeRange:
		switch nativeType {
		case domainentry.ConditionNativeTypeDate:
			return "date"
		case domainentry.ConditionNativeTypeNumber:
			return "number"
		default:
			return ""
		}
	case domainentry.ConditionValueShapeSingle:
		switch nativeType {
		case domainentry.ConditionNativeTypeBoolean:
			return "boolean"
		case domainentry.ConditionNativeTypeDate:
			return "date"
		case domainentry.ConditionNativeTypeNumber:
			return "number"
		case domainentry.ConditionNativeTypeString:
			return "text"
		default:
			return ""
		}
	case domainentry.ConditionValueShapeList:
		switch nativeType {
		case domainentry.ConditionNativeTypeCategorical:
			return "option_ref"
		case domainentry.ConditionNativeTypeString, domainentry.ConditionNativeTypeStringList:
			return "text"
		default:
			return ""
		}
	default:
		return ""
	}
}

func allOperandsAreActiveOptions(options []domainentry.PropertyOption, operands []string) bool {
	active := make(map[string]struct{}, len(options))
	for _, option := range options {
		if option.Active {
			active[option.OptionID.String()] = struct{}{}
		}
	}
	for _, operand := range operands {
		if _, ok := active[operand]; !ok {
			return false
		}
	}
	return true
}

func assignmentEmpty(fact domainentry.EntryPropertyAssignment) bool {
	if fact.State == domainentry.AssignmentStateUnset || fact.State == domainentry.AssignmentStateNull {
		return true
	}
	if fact.State != domainentry.AssignmentStateValue {
		return false
	}
	if fact.Scalar != nil {
		return fact.Scalar.Text != nil && *fact.Scalar.Text == ""
	}
	return fact.Many != nil && len(fact.Many) == 0
}

func assignmentStrings(fact domainentry.EntryPropertyAssignment) []string {
	values := []domainentry.AssignmentValue{}
	if fact.Scalar != nil {
		values = append(values, *fact.Scalar)
	} else {
		for _, member := range fact.Many {
			values = append(values, member.Value)
		}
	}
	out := make([]string, 0, len(values))
	for _, value := range values {
		switch {
		case value.Text != nil:
			out = append(out, *value.Text)
		case value.Decimal != nil:
			out = append(out, *value.Decimal)
		case value.Date != nil:
			out = append(out, *value.Date)
		case value.Boolean != nil:
			if *value.Boolean {
				out = append(out, "true")
			} else {
				out = append(out, "false")
			}
		case value.OptionID != nil:
			out = append(out, value.OptionID.String())
		}
	}
	return out
}

func compareOrdered(values []string, condition QueryCondition, nativeType domainentry.ConditionNativeType) bool {
	if len(values) != 1 {
		return false
	}
	operands := condition.Operand.Values
	if nativeType == domainentry.ConditionNativeTypeBoolean {
		if condition.Operand.Kind != "boolean" || condition.Operand.Boolean == nil || condition.Operator != "eq" {
			return false
		}
		return values[0] == map[bool]string{true: "true", false: "false"}[*condition.Operand.Boolean]
	}
	if len(operands) == 0 {
		return false
	}
	cmp := func(left, right string) int {
		if nativeType == domainentry.ConditionNativeTypeNumber {
			a, aok := new(big.Rat).SetString(left)
			b, bok := new(big.Rat).SetString(right)
			if !aok || !bok {
				return -2
			}
			return a.Cmp(b)
		}
		return strings.Compare(left, right)
	}
	c := cmp(values[0], operands[0])
	if c == -2 {
		return false
	}
	switch condition.Operator {
	case "eq":
		return c == 0
	case "neq":
		return c != 0
	case "gt":
		return c > 0
	case "gte":
		return c >= 0
	case "lt":
		return c < 0
	case "lte":
		return c <= 0
	case "btw", "nbtw":
		if len(operands) != 2 {
			return false
		}
		lower, upper := operands[0], operands[1]
		if cmp(lower, upper) > 0 {
			lower, upper = upper, lower
		}
		lowerComparison := cmp(values[0], lower)
		upperComparison := cmp(values[0], upper)
		if lowerComparison == -2 || upperComparison == -2 {
			return false
		}
		inside := lowerComparison >= 0 && upperComparison <= 0
		if condition.Operator == "nbtw" {
			return !inside
		}
		return inside
	}
	return false
}

func compareText(values []string, condition QueryCondition) bool {
	if len(values) != 1 || len(condition.Operand.Values) != 1 || condition.Operand.Kind != "text" {
		return false
	}
	value, operand := values[0], condition.Operand.Values[0]
	switch condition.Operator {
	case "cn":
		return strings.Contains(value, operand)
	case "nc":
		return !strings.Contains(value, operand)
	case "sw":
		return strings.HasPrefix(value, operand)
	case "ew":
		return strings.HasSuffix(value, operand)
	case "rx":
		operand = normalizeWildcardPattern(operand)
		pattern := regexp.QuoteMeta(operand)
		pattern = strings.ReplaceAll(pattern, `\*`, `.*`)
		matched, err := regexp.MatchString("^(?:"+pattern+")$", value)
		return err == nil && matched
	}
	return false
}

func normalizeWildcardPattern(pattern string) string {
	pattern = strings.ReplaceAll(pattern, `\.\*`, "*")
	pattern = strings.ReplaceAll(pattern, ".*", "*")
	return strings.ReplaceAll(pattern, "%", "*")
}

func containsAll(values, operands []string, substring bool) bool {
	for _, operand := range operands {
		if substring {
			found := false
			for _, value := range values {
				if strings.Contains(value, operand) {
					found = true
					break
				}
			}
			if !found {
				return false
			}
		} else if !containsString(values, operand) {
			return false
		}
	}
	return true
}
func containsAny(values, operands []string, substring bool) bool {
	for _, operand := range operands {
		for _, value := range values {
			if (substring && strings.Contains(value, operand)) || (!substring && value == operand) {
				return true
			}
		}
	}
	return false
}
func containsString(values []string, value string) bool {
	for _, candidate := range values {
		if candidate == value {
			return true
		}
	}
	return false
}
