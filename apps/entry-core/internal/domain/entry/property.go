package entry

import (
	"errors"
	"math/big"
	"regexp"
	"sort"
	"time"
	"unicode/utf8"
)

var (
	ErrInvalidPropertyDefinition = errors.New("invalid property definition")
	ErrInvalidValidationRule     = errors.New("invalid validation rule")
	ErrInvalidValidationResult   = errors.New("invalid validation result")
)

const (
	maximumValidationRules     = 32
	maximumAllowedOptions      = 256
	maximumPropertyItems       = 256
	maximumPropertyTextBytes   = 16384
	maximumPropertyScalarBytes = 256
	maximumDefinitionBudget    = 128 * 1024
	maximumValueBudget         = 4 * 1024 * 1024
)

type PropertyType = PropertyValueType

type PropertyCardinality string

const (
	PropertyCardinalityOne  PropertyCardinality = "one"
	PropertyCardinalityMany PropertyCardinality = "many"
)

func (cardinality PropertyCardinality) valid() bool {
	return cardinality == PropertyCardinalityOne || cardinality == PropertyCardinalityMany
}

type PropertyState string

const (
	PropertyStateValue         PropertyState = "value"
	PropertyStateNull          PropertyState = "null"
	PropertyStateUnknown       PropertyState = "unknown"
	PropertyStateError         PropertyState = "error"
	PropertyStateNotApplicable PropertyState = "not_applicable"
)

func (state PropertyState) valid() bool {
	switch state {
	case PropertyStateValue, PropertyStateNull, PropertyStateUnknown, PropertyStateError, PropertyStateNotApplicable:
		return true
	default:
		return false
	}
}

type PropertyProvenance string

const (
	PropertyProvenanceSystem          PropertyProvenance = "system"
	PropertyProvenanceFilesystem      PropertyProvenance = "filesystem"
	PropertyProvenanceSpotlight       PropertyProvenance = "spotlight"
	PropertyProvenanceExtracted       PropertyProvenance = "extracted"
	PropertyProvenanceUserDefined     PropertyProvenance = "user_defined"
	PropertyProvenanceProviderDefined PropertyProvenance = "provider_defined"
	PropertyProvenanceAgentGenerated  PropertyProvenance = "agent_generated"
)

func (provenance PropertyProvenance) valid() bool {
	switch provenance {
	case PropertyProvenanceSystem, PropertyProvenanceFilesystem, PropertyProvenanceSpotlight,
		PropertyProvenanceExtracted, PropertyProvenanceUserDefined, PropertyProvenanceProviderDefined,
		PropertyProvenanceAgentGenerated:
		return true
	default:
		return false
	}
}

type ValidationRuleKind string

const (
	ValidationRuleMinNumber      ValidationRuleKind = "min_number"
	ValidationRuleMaxNumber      ValidationRuleKind = "max_number"
	ValidationRuleMinLength      ValidationRuleKind = "min_length"
	ValidationRuleMaxLength      ValidationRuleKind = "max_length"
	ValidationRuleRegex          ValidationRuleKind = "regex"
	ValidationRuleAllowedOptions ValidationRuleKind = "allowed_options"
	ValidationRuleMaxItems       ValidationRuleKind = "max_items"
)

type ValidationRule struct {
	Kind           ValidationRuleKind
	DecimalOperand *string
	CountOperand   *int
	Pattern        *string
	AllowedOptions []string
}

func (rule ValidationRule) Validate(valueType PropertyType, cardinality PropertyCardinality) error {
	payloads := 0
	if rule.DecimalOperand != nil {
		payloads++
	}
	if rule.CountOperand != nil {
		payloads++
	}
	if rule.Pattern != nil {
		payloads++
	}
	if rule.AllowedOptions != nil {
		payloads++
	}
	if payloads != 1 {
		return ErrInvalidValidationRule
	}
	switch rule.Kind {
	case ValidationRuleMinNumber, ValidationRuleMaxNumber:
		if valueType != PropertyTypeNumber || rule.DecimalOperand == nil || !validCanonicalDecimal(*rule.DecimalOperand) {
			return ErrInvalidValidationRule
		}
	case ValidationRuleMinLength, ValidationRuleMaxLength:
		if valueType != PropertyTypeText || rule.CountOperand == nil || *rule.CountOperand < 0 || *rule.CountOperand > maximumPropertyTextBytes {
			return ErrInvalidValidationRule
		}
	case ValidationRuleRegex:
		if valueType != PropertyTypeText || rule.Pattern == nil || !validUTF8Bytes(*rule.Pattern, 1, 1024) {
			return ErrInvalidValidationRule
		}
		if _, err := regexp.Compile(*rule.Pattern); err != nil {
			return ErrInvalidValidationRule
		}
	case ValidationRuleAllowedOptions:
		if valueType != PropertyTypeSelect || !validAllowedOptions(rule.AllowedOptions) {
			return ErrInvalidValidationRule
		}
	case ValidationRuleMaxItems:
		if cardinality != PropertyCardinalityMany || rule.CountOperand == nil || *rule.CountOperand < 0 || *rule.CountOperand > maximumPropertyItems {
			return ErrInvalidValidationRule
		}
	default:
		return ErrInvalidValidationRule
	}
	return nil
}

type PropertyDefinition struct {
	PropertyID      PropertyID
	IdentityScheme  PropertyIdentityScheme
	Namespace       string
	Key             string
	DisplayName     string
	ValueType       PropertyType
	Cardinality     PropertyCardinality
	Required        bool
	Nullable        bool
	Editable        bool
	Provenance      PropertyProvenance
	ValidationRules []ValidationRule
	Unit            *string
}

func NewPropertyDefinition(definition PropertyDefinition) (PropertyDefinition, error) {
	if err := definition.Validate(); err != nil {
		return PropertyDefinition{}, err
	}
	return clonePropertyDefinition(definition), nil
}

func (definition PropertyDefinition) Validate() error {
	if !definition.PropertyID.valid() || !definition.IdentityScheme.valid() ||
		!definition.IdentityScheme.acceptsVersion(definition.PropertyID.version()) ||
		!validUTF8Bytes(definition.Namespace, 1, 128) ||
		!validUTF8Bytes(definition.Key, 1, 128) || !validUTF8Bytes(definition.DisplayName, 1, 256) ||
		!canonicalPropertyType(definition.ValueType) || !definition.Cardinality.valid() || !definition.Provenance.valid() ||
		len(definition.ValidationRules) > maximumValidationRules {
		return ErrInvalidPropertyDefinition
	}
	budget := len(definition.PropertyID.String()) + len(definition.Namespace) + len(definition.Key) + len(definition.DisplayName)
	if definition.Unit != nil {
		if !validUTF8Bytes(*definition.Unit, 1, 64) || !addWithin(&budget, len(*definition.Unit), maximumDefinitionBudget) {
			return ErrInvalidPropertyDefinition
		}
	}
	seen := make(map[ValidationRuleKind]struct{}, len(definition.ValidationRules))
	var minimumNumber, maximumNumber *string
	var minimumLength, maximumLength *int
	for _, rule := range definition.ValidationRules {
		if _, exists := seen[rule.Kind]; exists || rule.Validate(definition.ValueType, definition.Cardinality) != nil {
			return ErrInvalidPropertyDefinition
		}
		seen[rule.Kind] = struct{}{}
		if !addWithin(&budget, ruleBudget(rule), maximumDefinitionBudget) {
			return ErrInvalidPropertyDefinition
		}
		switch rule.Kind {
		case ValidationRuleMinNumber:
			minimumNumber = rule.DecimalOperand
		case ValidationRuleMaxNumber:
			maximumNumber = rule.DecimalOperand
		case ValidationRuleMinLength:
			minimumLength = rule.CountOperand
		case ValidationRuleMaxLength:
			maximumLength = rule.CountOperand
		}
	}
	if minimumNumber != nil && maximumNumber != nil && compareCanonicalDecimal(*minimumNumber, *maximumNumber) > 0 {
		return ErrInvalidPropertyDefinition
	}
	if minimumLength != nil && maximumLength != nil && *minimumLength > *maximumLength {
		return ErrInvalidPropertyDefinition
	}
	return nil
}

type ValidationReasonCode string

const (
	ValidationReasonTypeMismatch        ValidationReasonCode = "type_mismatch"
	ValidationReasonCardinalityMismatch ValidationReasonCode = "cardinality_mismatch"
	ValidationReasonRequiredMissing     ValidationReasonCode = "required_missing"
	ValidationReasonNullNotAllowed      ValidationReasonCode = "null_not_allowed"
	ValidationReasonMinNumber           ValidationReasonCode = "min_number"
	ValidationReasonMaxNumber           ValidationReasonCode = "max_number"
	ValidationReasonMinLength           ValidationReasonCode = "min_length"
	ValidationReasonMaxLength           ValidationReasonCode = "max_length"
	ValidationReasonRegexMismatch       ValidationReasonCode = "regex_mismatch"
	ValidationReasonOptionNotAllowed    ValidationReasonCode = "option_not_allowed"
	ValidationReasonMaxItems            ValidationReasonCode = "max_items"
	ValidationReasonInvalidDefinition   ValidationReasonCode = "invalid_definition"
)

type ValidationResult struct {
	Valid      bool
	ReasonCode ValidationReasonCode
	Message    string
	RuleKind   ValidationRuleKind
}

func (result ValidationResult) Validate() error {
	if result.Valid {
		if result.ReasonCode != "" || result.Message != "" || result.RuleKind != "" {
			return ErrInvalidValidationResult
		}
		return nil
	}
	if !validReasonCode(result.ReasonCode) || result.Message != stableValidationMessage(result.ReasonCode) {
		return ErrInvalidValidationResult
	}
	expectedRule := validationRuleForReason(result.ReasonCode)
	if result.RuleKind != expectedRule {
		return ErrInvalidValidationResult
	}
	return nil
}

type PropertyPayload struct {
	Text         *string
	Number       *string
	Date         *string
	DateTime     *string
	Boolean      *bool
	Select       *string
	TextMany     *[]string
	NumberMany   *[]string
	DateMany     *[]string
	DateTimeMany *[]string
	BooleanMany  *[]bool
	SelectMany   *[]string
}

func TextPayload(value string) PropertyPayload       { return PropertyPayload{Text: &value} }
func NumberPayload(value string) PropertyPayload     { return PropertyPayload{Number: &value} }
func DatePayload(value string) PropertyPayload       { return PropertyPayload{Date: &value} }
func DateTimePayload(value string) PropertyPayload   { return PropertyPayload{DateTime: &value} }
func BooleanPayload(value bool) PropertyPayload      { return PropertyPayload{Boolean: &value} }
func SelectPayload(value string) PropertyPayload     { return PropertyPayload{Select: &value} }
func TextManyPayload(value []string) PropertyPayload { return PropertyPayload{TextMany: &value} }
func NumberManyPayload(value []string) PropertyPayload {
	copied := append([]string(nil), value...)
	return PropertyPayload{NumberMany: &copied}
}
func DateManyPayload(value []string) PropertyPayload { return PropertyPayload{DateMany: &value} }
func DateTimeManyPayload(value []string) PropertyPayload {
	return PropertyPayload{DateTimeMany: &value}
}
func BooleanManyPayload(value []bool) PropertyPayload { return PropertyPayload{BooleanMany: &value} }
func SelectManyPayload(value []string) PropertyPayload {
	copied := append([]string(nil), value...)
	return PropertyPayload{SelectMany: &copied}
}

func (payload PropertyPayload) payloadCount() int {
	count := 0
	for _, present := range []bool{payload.Text != nil, payload.Number != nil, payload.Date != nil, payload.DateTime != nil,
		payload.Boolean != nil, payload.Select != nil, payload.TextMany != nil, payload.NumberMany != nil,
		payload.DateMany != nil, payload.DateTimeMany != nil, payload.BooleanMany != nil, payload.SelectMany != nil} {
		if present {
			count++
		}
	}
	return count
}

func NewPropertyValue(definition PropertyDefinition, entryID string, state PropertyState, provenance PropertyProvenance, observedAt time.Time, sourceRevision SourceRevision, editable bool, payload PropertyPayload) (PropertyValue, error) {
	if definition.Validate() != nil {
		return PropertyValue{}, ErrInvalidPropertyDefinition
	}
	definition = clonePropertyDefinition(definition)
	if !validPrefixedDigest(entryID, entryIDPrefix) || !state.valid() || !provenance.valid() || !validTimestamp(observedAt) || sourceRevision.Validate() != nil || (editable && !definition.Editable) {
		return PropertyValue{}, ErrInvalidPropertyValue
	}
	if !payloadWithinHardBounds(payload) {
		return PropertyValue{}, ErrInvalidPropertyValue
	}
	payload = normalizeDateTimePayload(payload)
	value := PropertyValue{
		Type: definition.ValueType, PropertyID: definition.PropertyID, EntryID: entryID, Payload: payload,
		State: state, Provenance: provenance, ObservedAt: observedAt.Round(0).UTC(), SourceRevision: sourceRevision,
		Editable: editable, Cardinality: definition.Cardinality,
	}
	value.Validation = ValidatePropertyValue(definition, &value)
	cloned := clonePropertyValue(value)
	if err := cloned.validateCanonicalShape(); err != nil {
		return PropertyValue{}, err
	}
	return cloned, nil
}

func ValidatePropertyValue(definition PropertyDefinition, value *PropertyValue) ValidationResult {
	if definition.Validate() != nil {
		return invalidResult(ValidationReasonInvalidDefinition, "")
	}
	if value == nil {
		if definition.Required {
			return invalidResult(ValidationReasonRequiredMissing, "")
		}
		return ValidationResult{Valid: true}
	}
	if value.PropertyID != definition.PropertyID || value.Type != definition.ValueType {
		return invalidResult(ValidationReasonTypeMismatch, "")
	}
	if !value.State.valid() {
		return invalidResult(ValidationReasonTypeMismatch, "")
	}
	if value.State != PropertyStateValue {
		if value.Payload.payloadCount() != 0 {
			return invalidResult(ValidationReasonTypeMismatch, "")
		}
		if value.State == PropertyStateNull && !definition.Nullable {
			return invalidResult(ValidationReasonNullNotAllowed, "")
		}
		if value.Cardinality != definition.Cardinality {
			return invalidResult(ValidationReasonCardinalityMismatch, "")
		}
		return ValidationResult{Valid: true}
	}
	if value.Cardinality != definition.Cardinality {
		return invalidResult(ValidationReasonCardinalityMismatch, "")
	}
	if value.Payload.payloadCount() != 1 || !payloadMatches(value.Payload, definition.ValueType, definition.Cardinality) {
		return invalidResult(ValidationReasonCardinalityMismatch, "")
	}
	if !payloadValuesValid(value.Payload, definition.ValueType, definition.Cardinality) {
		return invalidResult(ValidationReasonTypeMismatch, "")
	}
	return applyValidationRules(definition, value.Payload)
}

func (value PropertyValue) ValidateAgainst(definition PropertyDefinition) ValidationResult {
	return ValidatePropertyValue(definition, &value)
}

func (value PropertyValue) validateCanonicalShape() error {
	if value.StringValue != nil || value.Int64Value != nil || value.BoolValue != nil || value.TimestampValue != nil || value.StringListValue != nil {
		return ErrInvalidPropertyValue
	}
	if !canonicalPropertyType(value.Type) || !value.PropertyID.valid() || !validPrefixedDigest(value.EntryID, entryIDPrefix) ||
		!value.State.valid() || !value.Provenance.valid() || !validUTCTimestamp(value.ObservedAt) || value.SourceRevision.Validate() != nil ||
		!value.Cardinality.valid() || value.Validation.Validate() != nil || !payloadWithinHardBounds(value.Payload) {
		return ErrInvalidPropertyValue
	}
	if value.State == PropertyStateValue {
		if value.Payload.payloadCount() != 1 || !payloadMatches(value.Payload, value.Type, value.Cardinality) {
			return ErrInvalidPropertyValue
		}
	} else if value.Payload.payloadCount() != 0 {
		return ErrInvalidPropertyValue
	}
	return nil
}

func applyValidationRules(definition PropertyDefinition, payload PropertyPayload) ValidationResult {
	for _, kind := range []ValidationRuleKind{ValidationRuleMinNumber, ValidationRuleMaxNumber, ValidationRuleMinLength, ValidationRuleMaxLength, ValidationRuleRegex, ValidationRuleAllowedOptions, ValidationRuleMaxItems} {
		for _, rule := range definition.ValidationRules {
			if rule.Kind != kind {
				continue
			}
			if !rulePasses(rule, definition, payload) {
				switch kind {
				case ValidationRuleMinNumber:
					return invalidResult(ValidationReasonMinNumber, kind)
				case ValidationRuleMaxNumber:
					return invalidResult(ValidationReasonMaxNumber, kind)
				case ValidationRuleMinLength:
					return invalidResult(ValidationReasonMinLength, kind)
				case ValidationRuleMaxLength:
					return invalidResult(ValidationReasonMaxLength, kind)
				case ValidationRuleRegex:
					return invalidResult(ValidationReasonRegexMismatch, kind)
				case ValidationRuleAllowedOptions:
					return invalidResult(ValidationReasonOptionNotAllowed, kind)
				case ValidationRuleMaxItems:
					return invalidResult(ValidationReasonMaxItems, kind)
				}
			}
		}
	}
	return ValidationResult{Valid: true}
}

func rulePasses(rule ValidationRule, definition PropertyDefinition, payload PropertyPayload) bool {
	values := payloadStrings(payload, definition.ValueType, definition.Cardinality)
	switch rule.Kind {
	case ValidationRuleMinNumber:
		for _, value := range values {
			if compareCanonicalDecimal(value, *rule.DecimalOperand) < 0 {
				return false
			}
		}
	case ValidationRuleMaxNumber:
		for _, value := range values {
			if compareCanonicalDecimal(value, *rule.DecimalOperand) > 0 {
				return false
			}
		}
	case ValidationRuleMinLength:
		for _, value := range values {
			if utf8.RuneCountInString(value) < *rule.CountOperand {
				return false
			}
		}
	case ValidationRuleMaxLength:
		for _, value := range values {
			if utf8.RuneCountInString(value) > *rule.CountOperand {
				return false
			}
		}
	case ValidationRuleRegex:
		compiled, err := regexp.Compile(*rule.Pattern)
		if err != nil {
			return false
		}
		for _, value := range values {
			if !compiled.MatchString(value) {
				return false
			}
		}
	case ValidationRuleAllowedOptions:
		for _, value := range values {
			index := sort.SearchStrings(rule.AllowedOptions, value)
			if index == len(rule.AllowedOptions) || rule.AllowedOptions[index] != value {
				return false
			}
		}
	case ValidationRuleMaxItems:
		return payloadItemCount(payload) <= *rule.CountOperand
	}
	return true
}

func canonicalPropertyType(valueType PropertyType) bool {
	switch valueType {
	case PropertyTypeText, PropertyTypeNumber, PropertyTypeDate, PropertyTypeDateTime, PropertyTypeBoolean, PropertyTypeSelect:
		return true
	default:
		return false
	}
}

func validCanonicalDecimal(value string) bool {
	if len(value) < 1 || len(value) > 64 {
		return false
	}
	index := 0
	negative := false
	if value[0] == '-' {
		negative = true
		index++
	}
	if index == len(value) {
		return false
	}
	integerStart := index
	if value[index] == '0' {
		index++
		if index < len(value) && value[index] >= '0' && value[index] <= '9' {
			return false
		}
	} else {
		if value[index] < '1' || value[index] > '9' {
			return false
		}
		for index < len(value) && value[index] >= '0' && value[index] <= '9' {
			index++
		}
	}
	integerDigits := index - integerStart
	fractionDigits := 0
	if index < len(value) {
		if value[index] != '.' {
			return false
		}
		index++
		fractionStart := index
		for index < len(value) && value[index] >= '0' && value[index] <= '9' {
			index++
		}
		fractionDigits = index - fractionStart
		if fractionDigits < 1 || fractionDigits > 18 || value[index-1] == '0' {
			return false
		}
	}
	if index != len(value) || integerDigits+fractionDigits > 38 {
		return false
	}
	if negative && integerDigits == 1 && value[integerStart] == '0' && fractionDigits == 0 {
		return false
	}
	return true
}

func compareCanonicalDecimal(left, right string) int {
	leftValue, _ := new(big.Rat).SetString(left)
	rightValue, _ := new(big.Rat).SetString(right)
	return leftValue.Cmp(rightValue)
}

func validAllowedOptions(options []string) bool {
	if len(options) < 1 || len(options) > maximumAllowedOptions {
		return false
	}
	budget := 0
	for index, option := range options {
		if !validUTF8Bytes(option, 1, maximumPropertyScalarBytes) || !addWithin(&budget, len(option), maximumDefinitionBudget) {
			return false
		}
		if index > 0 && options[index-1] >= option {
			return false
		}
	}
	return true
}

func payloadMatches(payload PropertyPayload, valueType PropertyType, cardinality PropertyCardinality) bool {
	if cardinality == PropertyCardinalityOne {
		switch valueType {
		case PropertyTypeText:
			return payload.Text != nil
		case PropertyTypeNumber:
			return payload.Number != nil
		case PropertyTypeDate:
			return payload.Date != nil
		case PropertyTypeDateTime:
			return payload.DateTime != nil
		case PropertyTypeBoolean:
			return payload.Boolean != nil
		case PropertyTypeSelect:
			return payload.Select != nil
		}
	}
	switch valueType {
	case PropertyTypeText:
		return payload.TextMany != nil
	case PropertyTypeNumber:
		return payload.NumberMany != nil
	case PropertyTypeDate:
		return payload.DateMany != nil
	case PropertyTypeDateTime:
		return payload.DateTimeMany != nil
	case PropertyTypeBoolean:
		return payload.BooleanMany != nil
	case PropertyTypeSelect:
		return payload.SelectMany != nil
	default:
		return false
	}
}

func payloadValuesValid(payload PropertyPayload, valueType PropertyType, cardinality PropertyCardinality) bool {
	if payloadItemCount(payload) > maximumPropertyItems {
		return false
	}
	if valueType == PropertyTypeBoolean {
		return true
	}
	for _, value := range payloadStrings(payload, valueType, cardinality) {
		switch valueType {
		case PropertyTypeText:
			if !validUTF8Bytes(value, 0, maximumPropertyTextBytes) {
				return false
			}
		case PropertyTypeNumber:
			if !validCanonicalDecimal(value) {
				return false
			}
		case PropertyTypeDate:
			if !validDate(value) {
				return false
			}
		case PropertyTypeDateTime:
			if !validCanonicalDateTime(value) {
				return false
			}
		case PropertyTypeSelect:
			if !validUTF8Bytes(value, 1, maximumPropertyScalarBytes) {
				return false
			}
		}
	}
	return true
}

func payloadStrings(payload PropertyPayload, valueType PropertyType, cardinality PropertyCardinality) []string {
	if cardinality == PropertyCardinalityOne {
		switch valueType {
		case PropertyTypeText:
			if payload.Text != nil {
				return []string{*payload.Text}
			}
		case PropertyTypeNumber:
			if payload.Number != nil {
				return []string{*payload.Number}
			}
		case PropertyTypeDate:
			if payload.Date != nil {
				return []string{*payload.Date}
			}
		case PropertyTypeDateTime:
			if payload.DateTime != nil {
				return []string{*payload.DateTime}
			}
		case PropertyTypeSelect:
			if payload.Select != nil {
				return []string{*payload.Select}
			}
		}
		return nil
	}
	switch valueType {
	case PropertyTypeText:
		if payload.TextMany != nil {
			return *payload.TextMany
		}
	case PropertyTypeNumber:
		if payload.NumberMany != nil {
			return *payload.NumberMany
		}
	case PropertyTypeDate:
		if payload.DateMany != nil {
			return *payload.DateMany
		}
	case PropertyTypeDateTime:
		if payload.DateTimeMany != nil {
			return *payload.DateTimeMany
		}
	case PropertyTypeSelect:
		if payload.SelectMany != nil {
			return *payload.SelectMany
		}
	}
	return nil
}

func payloadItemCount(payload PropertyPayload) int {
	switch {
	case payload.TextMany != nil:
		return len(*payload.TextMany)
	case payload.NumberMany != nil:
		return len(*payload.NumberMany)
	case payload.DateMany != nil:
		return len(*payload.DateMany)
	case payload.DateTimeMany != nil:
		return len(*payload.DateTimeMany)
	case payload.BooleanMany != nil:
		return len(*payload.BooleanMany)
	case payload.SelectMany != nil:
		return len(*payload.SelectMany)
	case payload.payloadCount() == 1:
		return 1
	default:
		return 0
	}
}

func payloadWithinHardBounds(payload PropertyPayload) bool {
	if payload.payloadCount() > 1 || payloadItemCount(payload) > maximumPropertyItems {
		return false
	}
	budget := 0
	for _, value := range allPayloadStrings(payload) {
		if !utf8.ValidString(value) || !addWithin(&budget, len(value), maximumValueBudget) {
			return false
		}
	}
	return true
}

func allPayloadStrings(payload PropertyPayload) []string {
	values := make([]string, 0, payloadItemCount(payload))
	for _, scalar := range []*string{payload.Text, payload.Number, payload.Date, payload.DateTime, payload.Select} {
		if scalar != nil {
			values = append(values, *scalar)
		}
	}
	for _, list := range []*[]string{payload.TextMany, payload.NumberMany, payload.DateMany, payload.DateTimeMany, payload.SelectMany} {
		if list != nil {
			values = append(values, (*list)...)
		}
	}
	return values
}

func validDate(value string) bool {
	if len(value) != len("2006-01-02") {
		return false
	}
	parsed, err := time.Parse("2006-01-02", value)
	return err == nil && parsed.Format("2006-01-02") == value
}

func validCanonicalDateTime(value string) bool {
	parsed, err := time.Parse(time.RFC3339Nano, value)
	return err == nil && parsed.UTC().Format(time.RFC3339Nano) == value
}

func normalizeDateTimePayload(payload PropertyPayload) PropertyPayload {
	normalize := func(value *string) *string {
		if value == nil {
			return nil
		}
		parsed, err := time.Parse(time.RFC3339Nano, *value)
		if err != nil {
			return value
		}
		result := parsed.UTC().Format(time.RFC3339Nano)
		return &result
	}
	payload.DateTime = normalize(payload.DateTime)
	if payload.DateTimeMany != nil {
		values := make([]string, len(*payload.DateTimeMany))
		for index, value := range *payload.DateTimeMany {
			parsed, err := time.Parse(time.RFC3339Nano, value)
			if err == nil {
				values[index] = parsed.UTC().Format(time.RFC3339Nano)
			} else {
				values[index] = value
			}
		}
		payload.DateTimeMany = &values
	}
	return payload
}

func invalidResult(code ValidationReasonCode, rule ValidationRuleKind) ValidationResult {
	return ValidationResult{ReasonCode: code, Message: stableValidationMessage(code), RuleKind: rule}
}

func stableValidationMessage(code ValidationReasonCode) string {
	messages := map[ValidationReasonCode]string{
		ValidationReasonTypeMismatch:        "The property value has an invalid type.",
		ValidationReasonCardinalityMismatch: "The property value has invalid cardinality.",
		ValidationReasonRequiredMissing:     "A required property value is missing.",
		ValidationReasonNullNotAllowed:      "The property does not allow null.",
		ValidationReasonMinNumber:           "The property value is below the minimum.",
		ValidationReasonMaxNumber:           "The property value is above the maximum.",
		ValidationReasonMinLength:           "The property value is shorter than allowed.",
		ValidationReasonMaxLength:           "The property value is longer than allowed.",
		ValidationReasonRegexMismatch:       "The property value does not match the required pattern.",
		ValidationReasonOptionNotAllowed:    "The selected option is not allowed.",
		ValidationReasonMaxItems:            "The property value has too many items.",
		ValidationReasonInvalidDefinition:   "The property definition is invalid.",
	}
	return messages[code]
}

func validationRuleForReason(code ValidationReasonCode) ValidationRuleKind {
	switch code {
	case ValidationReasonMinNumber:
		return ValidationRuleMinNumber
	case ValidationReasonMaxNumber:
		return ValidationRuleMaxNumber
	case ValidationReasonMinLength:
		return ValidationRuleMinLength
	case ValidationReasonMaxLength:
		return ValidationRuleMaxLength
	case ValidationReasonRegexMismatch:
		return ValidationRuleRegex
	case ValidationReasonOptionNotAllowed:
		return ValidationRuleAllowedOptions
	case ValidationReasonMaxItems:
		return ValidationRuleMaxItems
	default:
		return ""
	}
}

func validReasonCode(code ValidationReasonCode) bool {
	switch code {
	case ValidationReasonTypeMismatch, ValidationReasonCardinalityMismatch, ValidationReasonRequiredMissing,
		ValidationReasonNullNotAllowed, ValidationReasonMinNumber, ValidationReasonMaxNumber,
		ValidationReasonMinLength, ValidationReasonMaxLength, ValidationReasonRegexMismatch,
		ValidationReasonOptionNotAllowed, ValidationReasonMaxItems, ValidationReasonInvalidDefinition:
		return true
	default:
		return false
	}
}

func clonePropertyDefinition(value PropertyDefinition) PropertyDefinition {
	cloned := value
	cloned.Unit = cloneString(value.Unit)
	cloned.ValidationRules = make([]ValidationRule, len(value.ValidationRules))
	for index, rule := range value.ValidationRules {
		cloned.ValidationRules[index] = cloneValidationRule(rule)
	}
	return cloned
}

func cloneValidationRule(value ValidationRule) ValidationRule {
	cloned := value
	cloned.DecimalOperand = cloneString(value.DecimalOperand)
	cloned.Pattern = cloneString(value.Pattern)
	if value.CountOperand != nil {
		copied := *value.CountOperand
		cloned.CountOperand = &copied
	}
	cloned.AllowedOptions = append([]string(nil), value.AllowedOptions...)
	return cloned
}

func clonePropertyPayload(value PropertyPayload) PropertyPayload {
	cloned := PropertyPayload{
		Text: cloneString(value.Text), Number: cloneString(value.Number), Date: cloneString(value.Date),
		DateTime: cloneString(value.DateTime), Select: cloneString(value.Select),
	}
	if value.Boolean != nil {
		copied := *value.Boolean
		cloned.Boolean = &copied
	}
	cloned.TextMany = cloneStringSlice(value.TextMany)
	cloned.NumberMany = cloneStringSlice(value.NumberMany)
	cloned.DateMany = cloneStringSlice(value.DateMany)
	cloned.DateTimeMany = cloneStringSlice(value.DateTimeMany)
	cloned.SelectMany = cloneStringSlice(value.SelectMany)
	if value.BooleanMany != nil {
		copied := append([]bool(nil), (*value.BooleanMany)...)
		cloned.BooleanMany = &copied
	}
	return cloned
}

func cloneStringSlice(value *[]string) *[]string {
	if value == nil {
		return nil
	}
	copied := append([]string(nil), (*value)...)
	return &copied
}

func ruleBudget(rule ValidationRule) int {
	budget := len(rule.Kind)
	if rule.DecimalOperand != nil {
		budget += len(*rule.DecimalOperand)
	}
	if rule.Pattern != nil {
		budget += len(*rule.Pattern)
	}
	for _, option := range rule.AllowedOptions {
		budget += len(option)
	}
	return budget
}

func addWithin(total *int, addition, maximum int) bool {
	if addition < 0 || *total > maximum-addition {
		return false
	}
	*total += addition
	return true
}

func EffectivePropertyEditable(definition PropertyDefinition, capabilities Capabilities, availability Availability, sourceEditable bool) bool {
	if definition.Validate() != nil || capabilities.ValidateCanonical() != nil || availability.ValidateCanonical() != nil {
		return false
	}
	return definition.Editable && sourceEditable && capabilities.Writable && availability.State == AvailabilityStateAvailable
}
