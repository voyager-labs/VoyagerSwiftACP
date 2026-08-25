package sqlite

import (
	"context"
	"crypto/rand"
	"time"

	"gorm.io/gorm"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// propertyPresetNamespace은 Status/Project/Priority 사전 설정 정의가 살아있는
// 워크스페이스 스코프 네임스페이스다. workspace_property_definitions의
// (workspace_id, namespace, canonical_key) 유일 키 덕에 Registry의 'system'
// 네임스페이스와 충돌하지 않고 워크스페이스마다 독립적으로 존재한다.
const propertyPresetNamespace = "preset"

// propertyPresetOption은 사전 설정 정의의 규정 선택지 하나다. Label은 사용자
// 재명명과 무관한 멱등 매칭 키이고 Ordinal은 기본 순서다.
type propertyPresetOption struct {
	Label   string
	Ordinal int
}

// propertyPresetDescriptor는 설치할 사전 설정 정의 하나의 불변 규격이다.
// CanonicalKey와 DisplayName은 첫 설치에만 사용되고 이후 재조정은 기존 행을
// 덮어쓰지 않는다. ValueType/Cardinality는 구조 완전성 테스트가 현재 값
// (select/one)과의 불변식을 검증하는 대상이다.
type propertyPresetDescriptor struct {
	Namespace    string
	CanonicalKey string
	DisplayName  string
	ValueType    string
	Cardinality  string
	Options      []propertyPresetOption
}

// propertyPresetDescriptors는 VOY-765 사전 설정 카탈로그 전체를 반환한다. 새
// 멤버를 추가하면 property_preset_test.go의 열거 테이블을 함께 갱신해야 한다.
func propertyPresetDescriptors() []propertyPresetDescriptor {
	return []propertyPresetDescriptor{
		{
			Namespace:    propertyPresetNamespace,
			CanonicalKey: "status",
			DisplayName:  "Status",
			ValueType:    "select",
			Cardinality:  "one",
			Options: []propertyPresetOption{
				{Label: "Backlog", Ordinal: 0},
				{Label: "Todo", Ordinal: 1},
				{Label: "In progress", Ordinal: 2},
				{Label: "Done", Ordinal: 3},
				{Label: "Canceled", Ordinal: 4},
			},
		},
		{
			// Project는 비어 있는 active 단일 선택 정의다(선택지는 사용자가 만든다).
			Namespace:    propertyPresetNamespace,
			CanonicalKey: "project",
			DisplayName:  "Project",
			ValueType:    "select",
			Cardinality:  "one",
			Options:      nil,
		},
		{
			Namespace:    propertyPresetNamespace,
			CanonicalKey: "priority",
			DisplayName:  "Priority",
			ValueType:    "select",
			Cardinality:  "one",
			Options: []propertyPresetOption{
				{Label: "No priority", Ordinal: 0},
				{Label: "Urgent", Ordinal: 1},
				{Label: "High", Ordinal: 2},
				{Label: "Medium", Ordinal: 3},
				{Label: "Low", Ordinal: 4},
			},
		},
	}
}

// newVoyagerIssuedID는 RFC 9562 version 7 + variant 비트의 16-byte UUIDv7을
// crypto/rand로 생성해 typed PropertyID로 반환한다. 도메인에 PropertyID 생성자가
// 없으므로 WorkspaceID.NewWorkspaceID와 동일한 바이트 레이아웃을 로컬에서
// 재현하고, 반환값은 도메인 valid/Parse 검증을 통과한다. 결정적 ID(v5/hash)를
// 쓰지 않아 데이터베이스마다 서로 다른 ID를 받는다.
func newVoyagerIssuedID() (domainentry.PropertyID, error) {
	var id domainentry.PropertyID
	now := time.Now().UnixMilli()
	id[0] = byte(now >> 40)
	id[1] = byte(now >> 32)
	id[2] = byte(now >> 24)
	id[3] = byte(now >> 16)
	id[4] = byte(now >> 8)
	id[5] = byte(now)
	if _, err := rand.Read(id[6:]); err != nil {
		return domainentry.PropertyID{}, err
	}
	id[6] = (id[6] & 0x0f) | 0x70
	id[8] = (id[8] & 0x3f) | 0x80
	return id, nil
}

// ApplyPropertyPresets는 Status/Project/Priority 사전 설정을 멱등하게
// 재조정한다. 전체 동작은 하나의 top-level Store.WithinTx 안에서 실행되므로
// 중간 실패는 부분 사전 설정을 남기지 않는다. 첫 실행은 누락 정의/선택지를
// voyager_issued UUIDv7로 만들고, 이후 실행은 누락 멤버만 추가하며 기존 행의
// ID·이름·레이블·순서·색·메타데이터·비활성 상태는 절대 덮어쓰지 않는다.
func (store *Store) ApplyPropertyPresets(ctx context.Context, wsctx domainentry.WorkspaceContext) error {
	return store.WithinTx(ctx, func(tx *gorm.DB) error {
		return applyPropertyPresetsInTx(tx, wsctx)
	})
}

// applyPropertyPresetsInTx는 tx-scoped *gorm.DB 위에서 사전 설정 재조정을
// 수행하는 커밋 경계 없는 원시 함수다. 재조정을 다른 트랜잭션과 조합할 수
// 있도록 패키지 수준으로 노출한다.
func applyPropertyPresetsInTx(tx *gorm.DB, wsctx domainentry.WorkspaceContext) error {
	if wsctx.ID == (domainentry.WorkspaceID{}) {
		return ErrInvalidPropertyRow
	}
	wsBytes := wsctx.ID.Bytes()
	now := tx.NowFunc()

	for _, descriptor := range propertyPresetDescriptors() {
		// 정의는 (workspace_id, namespace, canonical_key)로 멱등 매칭한다.
		var existing WorkspacePropertyDefinitionRow
		err := tx.Where(
			"workspace_id = ? AND namespace = ? AND canonical_key = ?",
			wsBytes, descriptor.Namespace, descriptor.CanonicalKey,
		).First(&existing).Error
		switch {
		case err == nil:
			// 기존 정의는 상태(이름·생명주기 포함)를 그대로 유지하고, 선택지
			// 재조정에는 그 property_id를 재사용한다.
		case err == gorm.ErrRecordNotFound:
			defID, genErr := newVoyagerIssuedID()
			if genErr != nil {
				return genErr
			}
			if createErr := tx.Create(&WorkspacePropertyDefinitionRow{
				WorkspaceID:        wsBytes,
				PropertyID:         defID.Bytes(),
				Origin:             "built_in",
				IdentityScheme:     string(domainentry.PropertyIdentitySchemeVoyagerIssued),
				Namespace:          descriptor.Namespace,
				CanonicalKey:       descriptor.CanonicalKey,
				DisplayName:        descriptor.DisplayName,
				Description:        "Voyager built-in single-select preset",
				ValueType:          descriptor.ValueType,
				Cardinality:        descriptor.Cardinality,
				Nullable:           false,
				Editable:           true,
				DefaultHidden:      false,
				DefaultPinned:      false,
				DBIndexedHint:      false,
				Provenance:         string(domainentry.PropertyProvenanceUserDefined),
				DefinitionRev:      1,
				LifecycleState:     "active",
				DefaultDisplayUnit: "",
				UnitsJSON:          "",
				CreatedAt:          now,
				UpdatedAt:          now,
			}).Error; createErr != nil {
				return createErr
			}
			existing = WorkspacePropertyDefinitionRow{
				WorkspaceID: wsBytes,
				PropertyID:  defID.Bytes(),
			}
		default:
			return err
		}

		if err := reconcilePresetOptions(tx, wsBytes, existing.PropertyID, descriptor.Options, now); err != nil {
			return err
		}
	}
	return nil
}

// reconcilePresetOptions는 정의의 규정 선택지 중 누락된 멤버만 만든다. 선택지는
// (workspace_id, property_id, label)로 멱등 매칭하며, 이미 있는 선택지(비활성
// 포함)는 ID·레이블·순서·색·활성 상태를 건드리지 않는다. 새 선택지는
// voyager_issued UUIDv7로 만들고 규정 순서가 이미 점유됐으면 다음 빈 순서를
// 쓴다(사용자 재정렬을 밀어내지 않는다).
func reconcilePresetOptions(
	tx *gorm.DB,
	wsBytes []byte,
	propertyID []byte,
	options []propertyPresetOption,
	now time.Time,
) error {
	usedOrdinals := make(map[int]struct{})
	var existingOptions []WorkspacePropertyOptionRow
	if err := tx.Where("workspace_id = ? AND property_id = ?", wsBytes, propertyID).
		Find(&existingOptions).Error; err != nil {
		return err
	}
	for _, option := range existingOptions {
		usedOrdinals[option.Ordinal] = struct{}{}
	}
	labels := make(map[string]struct{}, len(existingOptions))
	for _, option := range existingOptions {
		labels[option.Label] = struct{}{}
	}

	maxOrdinal := -1
	for ordinal := range usedOrdinals {
		if ordinal > maxOrdinal {
			maxOrdinal = ordinal
		}
	}

	for _, preset := range options {
		if _, exists := labels[preset.Label]; exists {
			continue
		}
		ordinal := preset.Ordinal
		if _, taken := usedOrdinals[ordinal]; taken {
			ordinal = maxOrdinal + 1
		}
		optionID, err := newVoyagerIssuedID()
		if err != nil {
			return err
		}
		if createErr := tx.Create(&WorkspacePropertyOptionRow{
			WorkspaceID: wsBytes,
			OptionID:    optionID.Bytes(),
			PropertyID:  propertyID,
			Label:       preset.Label,
			Color:       "",
			Ordinal:     ordinal,
			Active:      true,
			CreatedAt:   now,
			UpdatedAt:   now,
		}).Error; createErr != nil {
			return createErr
		}
		usedOrdinals[ordinal] = struct{}{}
		labels[preset.Label] = struct{}{}
		if ordinal > maxOrdinal {
			maxOrdinal = ordinal
		}
	}
	return nil
}
