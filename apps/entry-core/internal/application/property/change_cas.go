package property

import (
	"context"
	"sort"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// changeSnapshot은 한 시점의 정의·계약·현재 fact 읽기다. execute는 tx 안에서
// 다시 만들어 prepare 결과를 신뢰하지 않는다.
type changeSnapshot struct {
	definitions map[domainentry.PropertyID]domainentry.WorkspacePropertyDefinition
	contracts   map[domainentry.PropertyID]domainentry.AssignmentContract
	current     map[assignmentRef]*domainentry.EntryPropertyAssignment
}

// loadContracts는 정의 전체를 한 번의 batched 읽기로 로드하고 요청 Property만
// 남긴 뒤, select 정의의 활성 선택지로 쓰기 시점 계약을 만든다.
func (service *ChangeService) loadContracts(
	ctx context.Context,
	workspace domainentry.WorkspaceContext,
	propertyIDs []domainentry.PropertyID,
) (changeSnapshot, error) {
	wanted := make(map[domainentry.PropertyID]struct{}, len(propertyIDs))
	for _, id := range propertyIDs {
		wanted[id] = struct{}{}
	}
	all, err := service.catalog.Definitions(ctx, workspace)
	if err != nil {
		return changeSnapshot{}, err
	}
	definitions := make(map[domainentry.PropertyID]domainentry.WorkspacePropertyDefinition, len(propertyIDs))
	for _, definition := range all {
		if _, want := wanted[definition.PropertyID]; want {
			definitions[definition.PropertyID] = definition
		}
	}
	contracts := make(map[domainentry.PropertyID]domainentry.AssignmentContract, len(definitions))
	for id, definition := range definitions {
		options, err := service.catalog.Options(ctx, workspace, id)
		if err != nil {
			return changeSnapshot{}, err
		}
		contract := domainentry.AssignmentContract{
			Type:        definition.ValueType,
			Cardinality: definition.Cardinality,
			Nullable:    definition.Nullable,
		}
		if contract.Type == domainentry.PropertyTypeSelect {
			contract.ActiveOptions = make(map[domainentry.PropertyOptionID]struct{}, len(options))
			for _, option := range options {
				if option.Active {
					contract.ActiveOptions[option.OptionID] = struct{}{}
				}
			}
		}
		contracts[id] = contract
	}
	return changeSnapshot{definitions: definitions, contracts: contracts}, nil
}

// stageChanges는 현재 fact 위에 각 변경의 다음 상태를 계산하고 CAS와 도메인 검증을
// 적용한다. 첫 쓰기는 revision 1, 이후 set/replace/clear는 단조 증가다.
func stageChanges(
	workspace domainentry.WorkspaceContext,
	resolved []resolvedChange,
	snapshot changeSnapshot,
) ([]resolvedChange, error) {
	staged := make([]resolvedChange, 0, len(resolved))
	for _, change := range resolved {
		definition, ok := snapshot.definitions[change.input.PropertyID]
		if !ok {
			return nil, ErrDefinitionNotFound
		}
		if definition.Lifecycle != domainentry.PropertyLifecycleActive {
			return nil, ErrDefinitionInactive
		}
		if !definition.Editable {
			return nil, ErrDefinitionNotEditable
		}
		if change.input.ExpectedDefinitionRevision != definition.DefinitionRev {
			return nil, ErrStaleDefinitionRevision
		}
		before := snapshot.current[assignmentRef{entryID: change.entryID, propertyID: change.input.PropertyID}]
		currentRevision := uint64(0)
		if before != nil {
			currentRevision = uint64(before.RecordRevision)
		}
		if change.input.ExpectedAssignmentRevision != currentRevision {
			return nil, ErrStaleAssignmentRevision
		}
		contract, ok := snapshot.contracts[change.input.PropertyID]
		if !ok {
			return nil, ErrDefinitionNotFound
		}
		next, err := buildAfterFact(workspace, change, before, currentRevision)
		if err != nil {
			return nil, err
		}
		validated, err := domainentry.NewEntryPropertyAssignment(next, contract)
		if err != nil {
			return nil, err
		}
		change.before = before
		change.after = validated
		staged = append(staged, change)
	}
	return staged, nil
}

// buildAfterFact는 목표 상태의 다음 durable fact를 만든다. ValueContractRevision은
// 첫 쓰기에서 1이 되고 이후 기존 값을 보존한다.
func buildAfterFact(
	workspace domainentry.WorkspaceContext,
	change resolvedChange,
	before *domainentry.EntryPropertyAssignment,
	currentRevision uint64,
) (domainentry.EntryPropertyAssignment, error) {
	valueContractRevision := 1
	if before != nil {
		valueContractRevision = int(before.ValueContractRevision)
	}
	next := domainentry.EntryPropertyAssignment{
		WorkspaceID:           workspace.ID,
		EntryID:               change.entryID,
		PropertyID:            change.input.PropertyID,
		TargetKind:            change.targetKind,
		State:                 change.input.Desired.State,
		RecordRevision:        domainentry.RecordRevision(currentRevision + 1),
		ValueContractRevision: domainentry.ValueContractRevision(valueContractRevision),
	}
	switch next.State {
	case domainentry.AssignmentStateValue:
		if change.input.Desired.Scalar != nil {
			next.Scalar = change.input.Desired.Scalar
			return next, nil
		}
		next.Many = make([]domainentry.OrderedAssignmentValue, 0, len(change.input.Desired.Many))
		for ordinal, member := range change.input.Desired.Many {
			next.Many = append(next.Many, domainentry.OrderedAssignmentValue{Ordinal: ordinal, Value: member})
		}
		return next, nil
	case domainentry.AssignmentStateUnset, domainentry.AssignmentStateNull:
		return next, nil
	default:
		return domainentry.EntryPropertyAssignment{}, ErrInvalidChangeRequest
	}
}

// indexFacts는 batched fact 읽기를 참조 인덱스로 바꾼다.
func indexFacts(facts []domainentry.EntryPropertyAssignment) map[assignmentRef]*domainentry.EntryPropertyAssignment {
	index := make(map[assignmentRef]*domainentry.EntryPropertyAssignment, len(facts))
	for position := range facts {
		fact := facts[position]
		index[assignmentRef{entryID: fact.EntryID, propertyID: fact.PropertyID}] = &facts[position]
	}
	return index
}

// preparedChanges는 staged 변경을 공개 제안 모델로 옮긴다.
func preparedChanges(staged []resolvedChange) []PreparedChange {
	changes := make([]PreparedChange, 0, len(staged))
	for _, change := range staged {
		changes = append(changes, PreparedChange{
			EntryID:    change.entryID,
			PropertyID: change.input.PropertyID,
			Before:     change.before,
			After:      change.after,
		})
	}
	return changes
}

// anyDurableBefore는 기존 내구 값의 교체·clear가 포함되었는지 보고한다.
func anyDurableBefore(staged []resolvedChange) bool {
	for _, change := range staged {
		if change.before != nil && change.before.RecordRevision >= 1 {
			return true
		}
	}
	return false
}

// stagedFacts는 staged 변경을 일괄 쓰기 fact 배치로 모은다.
func stagedFacts(staged []resolvedChange) []domainentry.EntryPropertyAssignment {
	facts := make([]domainentry.EntryPropertyAssignment, 0, len(staged))
	for _, change := range staged {
		facts = append(facts, change.after)
	}
	return facts
}

// changeEntryIDs와 changePropertyIDs는 batched 읽기에 필요한 참조 집합을 모은다.
func changeEntryIDs(resolved []resolvedChange) []string {
	entryIDs := make([]string, 0, len(resolved))
	for _, change := range resolved {
		entryIDs = append(entryIDs, change.entryID)
	}
	return entryIDs
}

func changePropertyIDs(resolved []resolvedChange) []domainentry.PropertyID {
	propertyIDs := make([]domainentry.PropertyID, 0, len(resolved))
	for _, change := range resolved {
		propertyIDs = append(propertyIDs, change.input.PropertyID)
	}
	return propertyIDs
}

// sortFactsByProperty는 목록 읽기의 결정적 순서를 제공한다.
func sortFactsByProperty(facts []domainentry.EntryPropertyAssignment) {
	sort.Slice(facts, func(i, j int) bool {
		return facts[i].PropertyID.String() < facts[j].PropertyID.String()
	})
}
