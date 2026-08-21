package entry

import (
	"errors"
	"fmt"
	"strings"
	"testing"
	"time"
)

func TestPropertyDefinition(t *testing.T) {
	definition := validTextDefinition()
	definition.ValidationRules = []ValidationRule{
		{Kind: ValidationRuleMinLength, CountOperand: intPointer(1)},
		{Kind: ValidationRuleMaxLength, CountOperand: intPointer(4)},
		{Kind: ValidationRuleRegex, Pattern: stringPointer(`^[[:alpha:]]+$`)},
	}
	created, err := NewPropertyDefinition(definition)
	if err != nil {
		t.Fatal(err)
	}
	*definition.ValidationRules[0].CountOperand = 99
	if *created.ValidationRules[0].CountOperand != 1 {
		t.Fatal("definition aliases rule input")
	}

	invalid := []PropertyDefinition{
		func() PropertyDefinition {
			value := validTextDefinition()
			value.ValueType = PropertyType("string")
			return value
		}(),
		func() PropertyDefinition {
			value := validTextDefinition()
			value.ValidationRules = []ValidationRule{{Kind: ValidationRuleRegex, Pattern: stringPointer("(")}}
			return value
		}(),
		func() PropertyDefinition {
			value := validTextDefinition()
			value.ValidationRules = []ValidationRule{{Kind: ValidationRuleRegex, Pattern: stringPointer(`(a)\1`)}}
			return value
		}(),
		func() PropertyDefinition {
			value := validTextDefinition()
			value.ValidationRules = []ValidationRule{{Kind: ValidationRuleMinLength, CountOperand: intPointer(5)}, {Kind: ValidationRuleMaxLength, CountOperand: intPointer(4)}}
			return value
		}(),
		func() PropertyDefinition {
			value := validTextDefinition()
			value.ValidationRules = []ValidationRule{{Kind: ValidationRuleMinNumber, DecimalOperand: stringPointer("1")}}
			return value
		}(),
	}
	for index, value := range invalid {
		if _, err := NewPropertyDefinition(value); !errors.Is(err, ErrInvalidPropertyDefinition) {
			t.Fatalf("invalid[%d] error = %v", index, err)
		}
	}
}

func TestPropertyCatalogConstraints(t *testing.T) {
	definition := validSelectDefinition()
	options := []string{"a", "b"}
	definition.ValidationRules = []ValidationRule{{Kind: ValidationRuleAllowedOptions, AllowedOptions: options}}
	created, err := NewPropertyDefinition(definition)
	if err != nil {
		t.Fatal(err)
	}
	options[0] = "mutated"
	if created.ValidationRules[0].AllowedOptions[0] != "a" {
		t.Fatal("allowed options alias input")
	}

	for _, options := range [][]string{{}, {"b", "a"}, {"a", "a"}, {strings.Repeat("x", 257)}} {
		candidate := validSelectDefinition()
		candidate.ValidationRules = []ValidationRule{{Kind: ValidationRuleAllowedOptions, AllowedOptions: options}}
		if _, err := NewPropertyDefinition(candidate); !errors.Is(err, ErrInvalidPropertyDefinition) {
			t.Fatalf("options %#v error = %v", options, err)
		}
	}
	maximumOptions := make([]string, 256)
	for index := range maximumOptions {
		maximumOptions[index] = fmt.Sprintf("option-%03d", index)
	}
	maximumDefinition := validSelectDefinition()
	maximumDefinition.ValidationRules = []ValidationRule{{Kind: ValidationRuleAllowedOptions, AllowedOptions: maximumOptions}}
	if _, err := NewPropertyDefinition(maximumDefinition); err != nil {
		t.Fatalf("256 options: %v", err)
	}
	maximumOptions = append(maximumOptions, "option-256")
	maximumDefinition.ValidationRules[0].AllowedOptions = maximumOptions
	if _, err := NewPropertyDefinition(maximumDefinition); !errors.Is(err, ErrInvalidPropertyDefinition) {
		t.Fatalf("257 options error = %v", err)
	}

	tooMany := validTextDefinition()
	tooMany.ValidationRules = make([]ValidationRule, 33)
	if _, err := NewPropertyDefinition(tooMany); !errors.Is(err, ErrInvalidPropertyDefinition) {
		t.Fatalf("too many rules error = %v", err)
	}
}

func TestPropertyValueCanonical(t *testing.T) {
	entryID := validEntryID
	observedAt := time.Date(2026, time.August, 3, 1, 2, 3, 4, time.UTC)
	cases := []struct {
		name       string
		definition PropertyDefinition
		payload    PropertyPayload
	}{
		{name: "text", definition: validTextDefinition(), payload: TextPayload("")},
		{name: "number", definition: validNumberDefinition(), payload: NumberPayload("-12.34")},
		{name: "date", definition: definitionFor(PropertyTypeDate), payload: DatePayload("2026-08-03")},
		{name: "datetime", definition: definitionFor(PropertyTypeDateTime), payload: DateTimePayload("2026-08-03T10:02:03.000000004+09:00")},
		{name: "boolean false", definition: definitionFor(PropertyTypeBoolean), payload: BooleanPayload(false)},
		{name: "select", definition: validSelectDefinition(), payload: SelectPayload("a")},
	}
	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			value, err := NewPropertyValue(test.definition, entryID, PropertyStateValue, PropertyProvenanceSystem, observedAt, mustSourceRevision(t), test.definition.Editable, test.payload)
			if err != nil {
				t.Fatal(err)
			}
			if !value.Validation.Valid || value.Type != test.definition.ValueType || value.Cardinality != test.definition.Cardinality {
				t.Fatalf("value = %#v", value)
			}
			if test.definition.ValueType == PropertyTypeDateTime && *value.Payload.DateTime != "2026-08-03T01:02:03.000000004Z" {
				t.Fatalf("datetime not normalized: %q", *value.Payload.DateTime)
			}
			if value.Type == PropertyValueTypeString || value.Type == PropertyValueTypeInt64 || value.Type == PropertyValueTypeBool || value.Type == PropertyValueTypeTimestamp || value.Type == PropertyValueTypeStringList || value.StringValue != nil {
				t.Fatalf("canonical constructor emitted legacy semantics: %#v", value)
			}
		})
	}
}

func TestPropertyValueStates(t *testing.T) {
	definition := validTextDefinition()
	observedAt := time.Date(2026, time.August, 3, 1, 2, 3, 0, time.UTC)
	for _, state := range []PropertyState{PropertyStateUnknown, PropertyStateError, PropertyStateNotApplicable} {
		value, err := NewPropertyValue(definition, validEntryID, state, PropertyProvenanceFilesystem, observedAt, mustSourceRevision(t), false, PropertyPayload{})
		if err != nil || !value.Validation.Valid || value.Payload.payloadCount() != 0 {
			t.Fatalf("state %q = %#v, %v", state, value, err)
		}
	}
	nullValue, err := NewPropertyValue(definition, validEntryID, PropertyStateNull, PropertyProvenanceSystem, observedAt, mustSourceRevision(t), false, PropertyPayload{})
	if err != nil {
		t.Fatal(err)
	}
	if nullValue.Validation.Valid || nullValue.Validation.ReasonCode != ValidationReasonNullNotAllowed {
		t.Fatalf("null validation = %#v", nullValue.Validation)
	}
	unknownWithPayload := PropertyValue{PropertyID: definition.PropertyID, Type: definition.ValueType, Cardinality: definition.Cardinality, State: PropertyStateUnknown, Payload: TextPayload("")}
	validation := ValidatePropertyValue(definition, &unknownWithPayload)
	if validation.Valid || validation.ReasonCode != ValidationReasonTypeMismatch {
		t.Fatalf("unknown payload validation = %#v", validation)
	}
	if _, err := NewPropertyValue(definition, validEntryID, PropertyStateUnknown, PropertyProvenanceSystem, observedAt, mustSourceRevision(t), false, TextPayload("")); !errors.Is(err, ErrInvalidPropertyValue) {
		t.Fatalf("canonical constructor accepted non-value payload: %v", err)
	}
}

func TestPropertyValueClosedSetsAndPolicy(t *testing.T) {
	observedAt := time.Date(2026, time.August, 3, 1, 2, 3, 0, time.UTC)
	definition := validTextDefinition()
	definition.Required = true
	if result := ValidatePropertyValue(definition, nil); result.Valid || result.ReasonCode != ValidationReasonRequiredMissing {
		t.Fatalf("required missing validation = %#v", result)
	}
	for _, state := range []PropertyState{PropertyStateNull, PropertyStateUnknown, PropertyStateError, PropertyStateNotApplicable} {
		nonValueMismatch := PropertyValue{PropertyID: definition.PropertyID, Type: definition.ValueType, Cardinality: PropertyCardinalityMany, State: state}
		want := ValidationReasonCardinalityMismatch
		if state == PropertyStateNull {
			want = ValidationReasonNullNotAllowed
		}
		if result := ValidatePropertyValue(definition, &nonValueMismatch); result.Valid || result.ReasonCode != want {
			t.Fatalf("non-value validation for %q = %#v", state, result)
		}
	}
	definition.Nullable = true
	nullValue, err := NewPropertyValue(definition, validEntryID, PropertyStateNull, PropertyProvenanceSystem, observedAt, mustSourceRevision(t), false, PropertyPayload{})
	if err != nil || !nullValue.Validation.Valid {
		t.Fatalf("nullable value = %#v, %v", nullValue, err)
	}
	for _, provenance := range []PropertyProvenance{
		PropertyProvenanceSystem, PropertyProvenanceFilesystem, PropertyProvenanceSpotlight,
		PropertyProvenanceExtracted, PropertyProvenanceUserDefined, PropertyProvenanceProviderDefined,
		PropertyProvenanceAgentGenerated,
	} {
		if _, err := NewPropertyValue(validTextDefinition(), validEntryID, PropertyStateValue, provenance, observedAt, mustSourceRevision(t), false, TextPayload("value")); err != nil {
			t.Fatalf("provenance %q: %v", provenance, err)
		}
	}
	if _, err := NewPropertyValue(validTextDefinition(), validEntryID, PropertyStateValue, PropertyProvenance("provider"), observedAt, mustSourceRevision(t), false, TextPayload("value")); !errors.Is(err, ErrInvalidPropertyValue) {
		t.Fatalf("unknown provenance error = %v", err)
	}
	if _, err := NewPropertyValue(validTextDefinition(), validEntryID, PropertyState("missing"), PropertyProvenanceSystem, observedAt, mustSourceRevision(t), false, PropertyPayload{}); !errors.Is(err, ErrInvalidPropertyValue) {
		t.Fatalf("unknown state error = %v", err)
	}
	if _, err := NewPropertyValue(validTextDefinition(), validEntryID, PropertyStateValue, PropertyProvenanceSystem, observedAt, mustSourceRevision(t), true, TextPayload("value")); err != nil {
		t.Fatalf("definition-editable value error = %v", err)
	}
	nonEditable := validTextDefinition()
	nonEditable.Editable = false
	if _, err := NewPropertyValue(nonEditable, validEntryID, PropertyStateValue, PropertyProvenanceSystem, observedAt, mustSourceRevision(t), true, TextPayload("value")); !errors.Is(err, ErrInvalidPropertyValue) {
		t.Fatalf("editability widening error = %v", err)
	}
	observedRevision := Revision{Strength: RevisionStrengthObserved, Token: stringPointer("1")}
	if _, err := NewSourceRevision(observedRevision); !errors.Is(err, ErrInvalidSourceRevision) {
		t.Fatalf("observed source revision error = %v", err)
	}
	many := validTextDefinition()
	many.Cardinality = PropertyCardinalityMany
	candidate := PropertyValue{PropertyID: many.PropertyID, Type: many.ValueType, Cardinality: many.Cardinality, State: PropertyStateValue, Payload: TextPayload("scalar")}
	validation := ValidatePropertyValue(many, &candidate)
	if validation.Valid || validation.ReasonCode != ValidationReasonCardinalityMismatch {
		t.Fatalf("cardinality validation = %#v", validation)
	}
	if _, err := NewPropertyValue(many, validEntryID, PropertyStateValue, PropertyProvenanceSystem, observedAt, mustSourceRevision(t), false, TextPayload("scalar")); !errors.Is(err, ErrInvalidPropertyValue) {
		t.Fatalf("canonical constructor accepted cardinality mismatch: %v", err)
	}
}

func TestPropertyValueCanonicalIsolationAndRedaction(t *testing.T) {
	definition := validTextDefinition()
	value := mustCanonicalPropertyValue(t, definition, validEntryID, TextPayload("safe"))
	legacy := "legacy"
	value.StringValue = &legacy
	if err := value.Validate(); !errors.Is(err, ErrInvalidPropertyValue) {
		t.Fatalf("canonical value accepted legacy payload: %v", err)
	}
	legacyValue, err := NewStringPropertyValue("legacy")
	if err != nil {
		t.Fatal(err)
	}
	legacyValue.Payload = TextPayload("canonical")
	if err := legacyValue.Validate(); !errors.Is(err, ErrInvalidPropertyValue) {
		t.Fatalf("legacy value accepted canonical payload: %v", err)
	}
	canonicalValue := mustCanonicalPropertyValue(t, definition, validEntryID, TextPayload("canonical"))
	if err := (Property{Key: "legacy", Value: canonicalValue}).Validate(); !errors.Is(err, ErrInvalidProperty) {
		t.Fatalf("legacy property accepted canonical value: %v", err)
	}
	expectedMessages := map[ValidationReasonCode]string{
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
	for reason, expected := range expectedMessages {
		if actual := stableValidationMessage(reason); actual != expected {
			t.Fatalf("stable message for %q = %q, want %q", reason, actual, expected)
		}
	}
	invalidMessage := invalidResult(ValidationReasonTypeMismatch, "")
	invalidMessage.Message = "token=secret"
	if err := invalidMessage.Validate(); !errors.Is(err, ErrInvalidValidationResult) {
		t.Fatalf("validation accepted noncanonical message: %v", err)
	}
	missingRule := invalidResult(ValidationReasonRegexMismatch, ValidationRuleRegex)
	missingRule.RuleKind = ""
	if err := missingRule.Validate(); !errors.Is(err, ErrInvalidValidationResult) {
		t.Fatalf("validation accepted missing rule kind: %v", err)
	}
}

func TestPropertyValueEffectiveEditability(t *testing.T) {
	definition := validTextDefinition()
	writable := Capabilities{Readable: true, Writable: true}
	available := mustAvailability(t, AvailabilityStateAvailable)
	if !EffectivePropertyEditable(definition, writable, available, true) {
		t.Fatal("fully writable property is not editable")
	}
	for _, test := range []struct {
		definition     PropertyDefinition
		capabilities   Capabilities
		availability   Availability
		sourceEditable bool
	}{
		{definition: func() PropertyDefinition { value := definition; value.Editable = false; return value }(), capabilities: writable, availability: available, sourceEditable: true},
		{definition: definition, capabilities: Capabilities{Readable: true}, availability: available, sourceEditable: true},
		{definition: definition, capabilities: writable, availability: mustAvailability(t, AvailabilityStateReadOnly), sourceEditable: true},
		{definition: definition, capabilities: writable, availability: available, sourceEditable: false},
	} {
		if EffectivePropertyEditable(test.definition, test.capabilities, test.availability, test.sourceEditable) {
			t.Fatalf("editability widened for %#v", test)
		}
	}
}

func TestPropertyValueRules(t *testing.T) {
	observedAt := time.Date(2026, time.August, 3, 1, 2, 3, 0, time.UTC)
	tests := []struct {
		name       string
		definition PropertyDefinition
		payload    PropertyPayload
		reason     ValidationReasonCode
	}{
		{name: "min number", definition: numberDefinitionWith(ValidationRule{Kind: ValidationRuleMinNumber, DecimalOperand: stringPointer("10")}), payload: NumberPayload("9.99"), reason: ValidationReasonMinNumber},
		{name: "max number", definition: numberDefinitionWith(ValidationRule{Kind: ValidationRuleMaxNumber, DecimalOperand: stringPointer("10")}), payload: NumberPayload("10.01"), reason: ValidationReasonMaxNumber},
		{name: "unicode scalar length", definition: textDefinitionWith(ValidationRule{Kind: ValidationRuleMaxLength, CountOperand: intPointer(1)}), payload: TextPayload("가나"), reason: ValidationReasonMaxLength},
		{name: "regex", definition: textDefinitionWith(ValidationRule{Kind: ValidationRuleRegex, Pattern: stringPointer(`^[a-z]+$`)}), payload: TextPayload("ABC"), reason: ValidationReasonRegexMismatch},
		{name: "option", definition: selectDefinitionWith("a", "b"), payload: SelectPayload("c"), reason: ValidationReasonOptionNotAllowed},
		{name: "max items", definition: manyTextDefinitionWith(1), payload: TextManyPayload([]string{"a", "b"}), reason: ValidationReasonMaxItems},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			value, err := NewPropertyValue(test.definition, validEntryID, PropertyStateValue, PropertyProvenanceSystem, observedAt, mustSourceRevision(t), false, test.payload)
			if err != nil {
				t.Fatal(err)
			}
			if value.Validation.Valid || value.Validation.ReasonCode != test.reason || strings.Contains(value.Validation.Message, "ABC") || strings.Contains(value.Validation.Message, "10.01") {
				t.Fatalf("validation = %#v", value.Validation)
			}
		})
	}
}

func TestPropertyValueCanonicalFormats(t *testing.T) {
	observedAt := time.Date(2026, time.August, 3, 1, 2, 3, 0, time.UTC)
	for _, decimal := range []string{"+1", "01", "-0", "1.0", "1e3", "NaN", strings.Repeat("9", 39)} {
		value, err := NewPropertyValue(validNumberDefinition(), validEntryID, PropertyStateValue, PropertyProvenanceSystem, observedAt, mustSourceRevision(t), false, NumberPayload(decimal))
		if err != nil {
			t.Fatal(err)
		}
		if value.Validation.Valid {
			t.Fatalf("decimal %q accepted", decimal)
		}
	}
	for _, date := range []string{"2026-8-03", "2026-02-30", "2026-08-03T00:00:00Z"} {
		value, err := NewPropertyValue(definitionFor(PropertyTypeDate), validEntryID, PropertyStateValue, PropertyProvenanceSystem, observedAt, mustSourceRevision(t), false, DatePayload(date))
		if err != nil {
			t.Fatal(err)
		}
		if value.Validation.Valid {
			t.Fatalf("date %q accepted", date)
		}
	}
	for _, datetime := range []string{"2026-08-03 00:00:00Z", "2026-08-03T00:00:00", "2026-02-30T00:00:00Z"} {
		value, err := NewPropertyValue(definitionFor(PropertyTypeDateTime), validEntryID, PropertyStateValue, PropertyProvenanceSystem, observedAt, mustSourceRevision(t), false, DateTimePayload(datetime))
		if err != nil {
			t.Fatal(err)
		}
		if value.Validation.Valid {
			t.Fatalf("datetime %q accepted", datetime)
		}
	}
}

func TestPropertyValueDefensiveCopyAndBudget(t *testing.T) {
	definition := definitionFor(PropertyTypeText)
	definition.Cardinality = PropertyCardinalityMany
	items := []string{"a", "b"}
	value, err := NewPropertyValue(definition, validEntryID, PropertyStateValue, PropertyProvenanceSystem, time.Date(2026, 8, 3, 0, 0, 0, 0, time.UTC), mustSourceRevision(t), false, TextManyPayload(items))
	if err != nil {
		t.Fatal(err)
	}
	items[0] = "mutated"
	if (*value.Payload.TextMany)[0] != "a" {
		t.Fatal("property value aliases input")
	}
	oversized := make([]string, 257)
	if _, err := NewPropertyValue(definition, validEntryID, PropertyStateValue, PropertyProvenanceSystem, time.Date(2026, 8, 3, 0, 0, 0, 0, time.UTC), mustSourceRevision(t), false, TextManyPayload(oversized)); !errors.Is(err, ErrInvalidPropertyValue) {
		t.Fatalf("oversized payload error = %v", err)
	}
}

func validTextDefinition() PropertyDefinition   { return definitionFor(PropertyTypeText) }
func validNumberDefinition() PropertyDefinition { return definitionFor(PropertyTypeNumber) }
func validSelectDefinition() PropertyDefinition {
	value := definitionFor(PropertyTypeSelect)
	value.ValidationRules = []ValidationRule{{Kind: ValidationRuleAllowedOptions, AllowedOptions: []string{"a", "b"}}}
	return value
}
func definitionFor(valueType PropertyType) PropertyDefinition {
	return PropertyDefinition{PropertyID: "property.title", Namespace: "system", Key: "title", DisplayName: "Title", ValueType: valueType, Cardinality: PropertyCardinalityOne, Nullable: false, Editable: true, Provenance: PropertyProvenanceSystem, ValidationRules: []ValidationRule{}}
}
func textDefinitionWith(rule ValidationRule) PropertyDefinition {
	value := validTextDefinition()
	value.ValidationRules = []ValidationRule{rule}
	return value
}
func numberDefinitionWith(rule ValidationRule) PropertyDefinition {
	value := validNumberDefinition()
	value.ValidationRules = []ValidationRule{rule}
	return value
}
func selectDefinitionWith(options ...string) PropertyDefinition {
	value := definitionFor(PropertyTypeSelect)
	value.ValidationRules = []ValidationRule{{Kind: ValidationRuleAllowedOptions, AllowedOptions: options}}
	return value
}
func manyTextDefinitionWith(max int) PropertyDefinition {
	value := validTextDefinition()
	value.Cardinality = PropertyCardinalityMany
	value.ValidationRules = []ValidationRule{{Kind: ValidationRuleMaxItems, CountOperand: &max}}
	return value
}
func intPointer(value int) *int { return &value }
func mustCanonicalPropertyValue(t *testing.T, definition PropertyDefinition, entryID string, payload PropertyPayload) PropertyValue {
	t.Helper()
	value, err := NewPropertyValue(definition, entryID, PropertyStateValue, PropertyProvenanceSystem, time.Date(2026, 8, 3, 0, 0, 0, 0, time.UTC), mustSourceRevision(t), false, payload)
	if err != nil {
		t.Fatal(err)
	}
	if !value.Validation.Valid {
		t.Fatalf("validation = %#v", value.Validation)
	}
	return value
}

func TestPropertyValidationOrder(t *testing.T) {
	definition := validTextDefinition()
	definition.Required = true
	value := PropertyValue{PropertyID: definition.PropertyID, Type: definition.ValueType, Cardinality: PropertyCardinalityMany, State: PropertyStateNull, Payload: TextPayload("secret")}
	result := ValidatePropertyValue(definition, &value)
	if result.Valid || result.ReasonCode != ValidationReasonTypeMismatch {
		t.Fatalf("payload/state must precede cardinality: %#v", result)
	}
	value.Payload = PropertyPayload{}
	result = ValidatePropertyValue(definition, &value)
	if result.Valid || result.ReasonCode != ValidationReasonNullNotAllowed {
		t.Fatalf("nullability must precede cardinality: %#v", result)
	}
	value.State = PropertyState("future")
	result = ValidatePropertyValue(definition, &value)
	if result.Valid || result.ReasonCode != ValidationReasonTypeMismatch {
		t.Fatalf("state must precede cardinality: %#v", result)
	}
}
