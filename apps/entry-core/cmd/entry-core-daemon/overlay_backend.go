package main

import (
	"context"
	"errors"
	"time"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	sqlite "github.com/voyager-labs/voyager-app/apps/entry-core/internal/persistence/sqlite"
)

// 이 파일은 Entry 읽기에 끼워 넣는 Property overlay의 SQLite backend다.
// applicationproperty.PropertyOverlayReader 포트(그리고 동형인
// applicationentry.PropertyOverlayLoader)를 구현하며, durable assignment fact를
// canonical PropertyValue로 투영한다.

var (
	// errOverlayUnknownDefinition은 overlay fact가 참조한 정의가 저장소에 없는
	// 참조 무결성 위반이다. 메타데이터 전용 센티널이다.
	errOverlayUnknownDefinition = errors.New("overlay fact references unknown property definition")
	// errOverlayUnsupportedState는 변환기가 다루지 않는 assignment 상태를 받은
	// 프로그래밍 오류다. unset은 overlay 단계에서 미리 생략된다.
	errOverlayUnsupportedState = errors.New("unsupported assignment state for property overlay")
	// errOverlayPayloadMissing은 value 상태인 fact에 payload 멤버가 없는 저장소
	// 계약 위반이다.
	errOverlayPayloadMissing = errors.New("property overlay fact is missing its value payload")
	// errOverlayPayloadAmbiguous는 scalar와 many가 동시에 설정된 fact를 거절하는
	// 저장소 계약 위반이다.
	errOverlayPayloadAmbiguous = errors.New("property overlay fact has ambiguous value payload")
	// errOverlayPayloadKindMismatch는 정의 유형과 값 종류가 어긋난 fact를 거절하는
	// 저장소 계약 위반이다.
	errOverlayPayloadKindMismatch = errors.New("property overlay fact value kind does not match definition type")
)

// propertyOverlayStore는 batched overlay 로드의 SQLite backend 구현이다.
type propertyOverlayStore struct {
	catalog *sqlite.PropertyCatalogStore
	facts   *sqlite.EntryPropertyFactStore
}

// overlayObservation은 권위 사실 밖에서 채워지는 관측 봉투다. overlay 투영은
// 저장된 사실에 관측 메타데이터가 없으므로 로드 시점 값으로 채운다.
type overlayObservation struct {
	observedAt     time.Time
	sourceRevision domainentry.SourceRevision
}

// LoadOverlay는 요청 (entry, property) 집합의 durable fact를 읽어 entry별
// PropertyValue 목록으로 돌려준다. durable unset은 값이 없으므로 overlay에서
// 생략되고, 관측 봉투(관측 시각·source revision)는 권위 사실 밖 값으로 채운다.
func (s propertyOverlayStore) LoadOverlay(
	ctx context.Context,
	workspace domainentry.WorkspaceContext,
	entryIDs []string,
	propertyIDs []domainentry.PropertyID,
) (map[string][]domainentry.PropertyValue, error) {
	rows := make(map[string][]domainentry.PropertyValue)
	if len(entryIDs) == 0 || len(propertyIDs) == 0 {
		return rows, nil
	}
	// 정의 조회는 overlay 대상 property(요청 ID ≤256)로 한정한다. 전체
	// 카탈로그를 읽으면 요청당 두 번째 무제한 스캔이 된다. 비활성 정의도
	// read-back 투영에 필요하다.
	definitions, _, _, err := s.catalog.DefinitionsPage(ctx, workspace, false, propertyIDs, nil, len(propertyIDs))
	if err != nil {
		return nil, err
	}
	index := make(map[domainentry.PropertyID]domainentry.WorkspacePropertyDefinition, len(definitions))
	for _, definition := range definitions {
		index[definition.PropertyID] = definition
	}
	facts, err := s.facts.LoadAssignments(ctx, workspace, entryIDs, propertyIDs)
	if err != nil {
		return nil, err
	}
	revision, err := domainentry.NewRevision(domainentry.RevisionStrengthUnknown, nil)
	if err != nil {
		return nil, err
	}
	sourceRevision, err := domainentry.NewSourceRevision(revision)
	if err != nil {
		return nil, err
	}
	observation := overlayObservation{observedAt: time.Now().Round(0).UTC(), sourceRevision: sourceRevision}
	for _, fact := range facts {
		if fact.State == domainentry.AssignmentStateUnset {
			continue
		}
		definition, ok := index[fact.PropertyID]
		if !ok {
			return nil, errOverlayUnknownDefinition
		}
		value, convertErr := assignmentFactToPropertyValue(definition, fact, observation)
		if convertErr != nil {
			return nil, convertErr
		}
		rows[fact.EntryID] = append(rows[fact.EntryID], value)
	}
	return rows, nil
}

// assignmentFactToPropertyValue는 assignment 권위 사실 하나를 정의 계약과 합성해
// canonical PropertyValue로 투영한다. null은 nullable 정의에서만 유효하고 그 외
// 불변식 위반은 도메인 생성자가 실패 닫기한다.
func assignmentFactToPropertyValue(
	definition domainentry.WorkspacePropertyDefinition,
	fact domainentry.EntryPropertyAssignment,
	observation overlayObservation,
) (domainentry.PropertyValue, error) {
	var state domainentry.PropertyState
	switch fact.State {
	case domainentry.AssignmentStateNull:
		state = domainentry.PropertyStateNull
	case domainentry.AssignmentStateValue:
		state = domainentry.PropertyStateValue
	default:
		return domainentry.PropertyValue{}, errOverlayUnsupportedState
	}
	payload, err := overlayPayload(definition.ValueType, fact)
	if err != nil {
		return domainentry.PropertyValue{}, err
	}
	return domainentry.NewPropertyValue(
		propertyDefinitionForOverlay(definition), fact.EntryID, state,
		domainentry.PropertyProvenanceUserDefined, observation.observedAt,
		observation.sourceRevision, definition.Editable, payload,
	)
}

// overlayPayload는 fact의 scalar/many 멤버를 정의 유형에 맞는 payload로 사상한다.
// 유형×멤버 스위치는 열거형 전체를 다루며 default는 실패 닫기다.
func overlayPayload(valueType domainentry.PropertyType, fact domainentry.EntryPropertyAssignment) (domainentry.PropertyPayload, error) {
	if fact.Scalar == nil && fact.Many == nil {
		if fact.State == domainentry.AssignmentStateNull {
			return domainentry.PropertyPayload{}, nil
		}
		return domainentry.PropertyPayload{}, errOverlayPayloadMissing
	}
	if fact.Scalar != nil && fact.Many != nil {
		return domainentry.PropertyPayload{}, errOverlayPayloadAmbiguous
	}
	if fact.Scalar != nil {
		return scalarOverlayPayload(valueType, fact.Scalar)
	}
	return manyOverlayPayload(valueType, fact.Many)
}

// scalarOverlayPayload는 scalar 멤버 하나를 정의 유형별 payload로 사상한다.
func scalarOverlayPayload(valueType domainentry.PropertyType, value *domainentry.AssignmentValue) (domainentry.PropertyPayload, error) {
	switch valueType {
	case domainentry.PropertyTypeText:
		if value.Text == nil {
			return domainentry.PropertyPayload{}, errOverlayPayloadKindMismatch
		}
		return domainentry.TextPayload(*value.Text), nil
	case domainentry.PropertyTypeNumber:
		if value.Decimal == nil {
			return domainentry.PropertyPayload{}, errOverlayPayloadKindMismatch
		}
		return domainentry.NumberPayload(*value.Decimal), nil
	case domainentry.PropertyTypeDate:
		if value.Date == nil {
			return domainentry.PropertyPayload{}, errOverlayPayloadKindMismatch
		}
		return domainentry.DatePayload(*value.Date), nil
	case domainentry.PropertyTypeDateTime:
		if value.Timestamp == nil {
			return domainentry.PropertyPayload{}, errOverlayPayloadKindMismatch
		}
		return domainentry.DateTimePayload(*value.Timestamp), nil
	case domainentry.PropertyTypeBoolean:
		if value.Boolean == nil {
			return domainentry.PropertyPayload{}, errOverlayPayloadKindMismatch
		}
		return domainentry.BooleanPayload(*value.Boolean), nil
	case domainentry.PropertyTypeSelect:
		if value.OptionID == nil {
			return domainentry.PropertyPayload{}, errOverlayPayloadKindMismatch
		}
		return domainentry.SelectPayload(value.OptionID.String()), nil
	default:
		return domainentry.PropertyPayload{}, errOverlayPayloadKindMismatch
	}
}

// manyOverlayPayload는 ordered many 멤버들을 ordinal 순서 그대로 many payload로
// 사상한다.
func manyOverlayPayload(valueType domainentry.PropertyType, values []domainentry.OrderedAssignmentValue) (domainentry.PropertyPayload, error) {
	switch valueType {
	case domainentry.PropertyTypeText:
		member := make([]string, 0, len(values))
		for _, item := range values {
			if item.Value.Text == nil {
				return domainentry.PropertyPayload{}, errOverlayPayloadKindMismatch
			}
			member = append(member, *item.Value.Text)
		}
		return domainentry.TextManyPayload(member), nil
	case domainentry.PropertyTypeNumber:
		member := make([]string, 0, len(values))
		for _, item := range values {
			if item.Value.Decimal == nil {
				return domainentry.PropertyPayload{}, errOverlayPayloadKindMismatch
			}
			member = append(member, *item.Value.Decimal)
		}
		return domainentry.NumberManyPayload(member), nil
	case domainentry.PropertyTypeDate:
		member := make([]string, 0, len(values))
		for _, item := range values {
			if item.Value.Date == nil {
				return domainentry.PropertyPayload{}, errOverlayPayloadKindMismatch
			}
			member = append(member, *item.Value.Date)
		}
		return domainentry.DateManyPayload(member), nil
	case domainentry.PropertyTypeDateTime:
		member := make([]string, 0, len(values))
		for _, item := range values {
			if item.Value.Timestamp == nil {
				return domainentry.PropertyPayload{}, errOverlayPayloadKindMismatch
			}
			member = append(member, *item.Value.Timestamp)
		}
		return domainentry.DateTimeManyPayload(member), nil
	case domainentry.PropertyTypeBoolean:
		member := make([]bool, 0, len(values))
		for _, item := range values {
			if item.Value.Boolean == nil {
				return domainentry.PropertyPayload{}, errOverlayPayloadKindMismatch
			}
			member = append(member, *item.Value.Boolean)
		}
		return domainentry.BooleanManyPayload(member), nil
	case domainentry.PropertyTypeSelect:
		member := make([]string, 0, len(values))
		for _, item := range values {
			if item.Value.OptionID == nil {
				return domainentry.PropertyPayload{}, errOverlayPayloadKindMismatch
			}
			member = append(member, item.Value.OptionID.String())
		}
		return domainentry.SelectManyPayload(member), nil
	default:
		return domainentry.PropertyPayload{}, errOverlayPayloadKindMismatch
	}
}

// propertyDefinitionForOverlay는 카탈로그 정의를 PropertyValue 생성자가 요구하는
// 정의 표현으로 투영한다. 검증 규칙은 저장 행이 갖지 않으므로 빈 집합으로 둔다.
func propertyDefinitionForOverlay(definition domainentry.WorkspacePropertyDefinition) domainentry.PropertyDefinition {
	return domainentry.PropertyDefinition{
		PropertyID:         definition.PropertyID,
		IdentityScheme:     definition.IdentityScheme,
		Namespace:          definition.Namespace,
		Key:                definition.CanonicalKey,
		DisplayName:        definition.DisplayName,
		ValueType:          definition.ValueType,
		Cardinality:        definition.Cardinality,
		Editable:           definition.Editable,
		Nullable:           definition.Nullable,
		Provenance:         definition.Provenance,
		ValidationRules:    []domainentry.ValidationRule{},
		Unit:               definition.Unit,
		DefaultDisplayUnit: definition.DefaultDisplayUnit,
		Units:              definition.Units,
	}
}
