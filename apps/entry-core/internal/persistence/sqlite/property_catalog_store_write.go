package sqlite

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"gorm.io/gorm"

	applicationproperty "github.com/voyager-labs/voyager-app/apps/entry-core/internal/application/property"
	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// 이 파일은 PropertyCatalogStore의 쓰기 절반과 domain→row 역방향 mapper를
// 소유한다. 물리 삭제 경로는 계약상 없으며 create/update만 존재한다.

// PutDefinition은 새 정의 행을 만든다. seed provenance trio는 사용자 정의
// 규약(all NULL)으로 둔다.
func (s *PropertyCatalogStore) PutDefinition(ctx context.Context, definition domainentry.WorkspacePropertyDefinition) error {
	db, err := s.session(ctx)
	if err != nil {
		return err
	}
	row, rowErr := definitionToRow(definition, s.workspace.ID.Bytes(), nil, time.Now())
	if rowErr != nil {
		return rowErr
	}
	return db.Create(&row).Error
}

// SaveDefinition은 존재하는 정의 행을 domain 값으로 갱신한다. seed provenance
// trio와 created_at은 기존 행 값을 보존하고 나머지 매핑 열은 전부 대체한다.
// 행이 없으면 실패 닫기한다.
func (s *PropertyCatalogStore) SaveDefinition(ctx context.Context, definition domainentry.WorkspacePropertyDefinition) error {
	db, err := s.session(ctx)
	if err != nil {
		return err
	}
	var existing WorkspacePropertyDefinitionRow
	queryErr := db.Where(
		"workspace_id = ? AND property_id = ?", s.workspace.ID.Bytes(), definition.PropertyID.Bytes(),
	).First(&existing).Error
	if errors.Is(queryErr, gorm.ErrRecordNotFound) {
		return applicationproperty.ErrDefinitionNotFound
	}
	if queryErr != nil {
		return queryErr
	}
	row, rowErr := definitionToRow(definition, s.workspace.ID.Bytes(), &existing, time.Now())
	if rowErr != nil {
		return rowErr
	}
	return db.Save(&row).Error
}

// PutOption은 새 선택지 행을 만든다.
func (s *PropertyCatalogStore) PutOption(ctx context.Context, option domainentry.PropertyOption) error {
	db, err := s.session(ctx)
	if err != nil {
		return err
	}
	row, rowErr := optionToRow(option, s.workspace.ID.Bytes(), time.Now())
	if rowErr != nil {
		return rowErr
	}
	return db.Create(&row).Error
}

// SaveOptions은 존재하는 선택지 행들을 domain 값으로 치환 갱신한다. 생성은
// PutOption의 소관이고 물리 삭제 경로는 계약상 없으므로, 없는 행에 대한 갱신은
// 실패 닫기한다. assignment 값 행의 FK 참조를 깨지 않기 위해 delete 후 재삽입이
// 아닌 update만 수행한다.
// optionOrdinalShift는 SaveOptions 2단계 갱신의 임시 ordinal 오프셋이다.
const optionOrdinalShift = 1 << 20

func (s *PropertyCatalogStore) SaveOptions(ctx context.Context, options []domainentry.PropertyOption) error {
	db, err := s.session(ctx)
	if err != nil {
		return err
	}
	// UNIQUE(workspace_id, property_id, ordinal) 인덱스와 ordinal >= 0 CHECK는
	// 순열 치환의 중간 상태(두 행이 같은 ordinal을 지나가는 순간, 음수 치환값)를
	// 허용하지 않는다. 같은 tx 안에서 도달 불가능한 큰 양수 치환값으로 전부
	// 비켜난 뒤 최종 값을 쓰는 2단계 갱신으로 임시 충돌을 제거한다. 도메인
	// 검증이 활성 선택지 ordinal을 0..n-1 연속으로 강제하므로 이 오프셋은 본
	// 값과 절대 충돌하지 않는다.
	for index, option := range options {
		row, rowErr := optionToRow(option, s.workspace.ID.Bytes(), time.Now())
		if rowErr != nil {
			return rowErr
		}
		result := db.Model(&WorkspacePropertyOptionRow{}).Where(
			"workspace_id = ? AND option_id = ?", row.WorkspaceID, row.OptionID,
		).Updates(map[string]any{"ordinal": optionOrdinalShift + index})
		if result.Error != nil {
			return result.Error
		}
		if result.RowsAffected != 1 {
			return applicationproperty.ErrOptionNotFound
		}
	}
	for _, option := range options {
		row, rowErr := optionToRow(option, s.workspace.ID.Bytes(), time.Now())
		if rowErr != nil {
			return rowErr
		}
		result := db.Model(&WorkspacePropertyOptionRow{}).Where(
			"workspace_id = ? AND option_id = ?", row.WorkspaceID, row.OptionID,
		).Updates(map[string]any{
			"label": row.Label, "color": row.Color, "ordinal": row.Ordinal,
			"active": row.Active, "updated_at": row.UpdatedAt,
		})
		if result.Error != nil {
			return result.Error
		}
		if result.RowsAffected != 1 {
			return applicationproperty.ErrOptionNotFound
		}
	}
	return nil
}

// definitionToRow는 domain 정의를 GORM 행으로 매핑한다. existing이 nil이면 새
// 행(seed trio NULL, created_at=now)을 만들고, 아니면 seed trio와 created_at을
// 보존한다. provenance 열에는 원본 문자열(MappingProvenance)을 그대로 저장해
// 시드 digest 프레이밍과 왕복 일치를 유지한다.
func definitionToRow(definition domainentry.WorkspacePropertyDefinition, workspace []byte, existing *WorkspacePropertyDefinitionRow, now time.Time) (WorkspacePropertyDefinitionRow, error) {
	if err := definition.Validate(); err != nil {
		return WorkspacePropertyDefinitionRow{}, ErrInvalidCatalogRow
	}
	unitsJSON, err := encodeUnitsJSON(definition.Units)
	if err != nil {
		return WorkspacePropertyDefinitionRow{}, ErrInvalidCatalogRow
	}
	// provenance 열에는 원본 문자열(MappingProvenance)을 저장한다. 시드 행은
	// verbatim 문자열을 보존하고, 매핑 문자열 없이 enum만 채운 도메인 생성자
	// (예: CreateDefinition)는 enum 값을 열에 쓴다. 빈 문자열은 읽기 쪽
	// provenance enum 검증을 실패시키므로 절대 저장하지 않는다.
	rowProvenance := definition.MappingProvenance
	if rowProvenance == "" {
		rowProvenance = string(definition.Provenance)
	}
	row := WorkspacePropertyDefinitionRow{
		WorkspaceID:        workspace,
		PropertyID:         definition.PropertyID.Bytes(),
		Origin:             string(definition.Origin),
		IdentityScheme:     string(definition.IdentityScheme),
		Namespace:          definition.Namespace,
		CanonicalKey:       definition.CanonicalKey,
		DisplayName:        definition.DisplayName,
		Description:        definition.Description,
		ValueType:          string(definition.ValueType),
		Cardinality:        string(definition.Cardinality),
		Nullable:           definition.Nullable,
		Editable:           definition.Editable,
		DefaultHidden:      definition.DefaultHidden,
		DefaultPinned:      definition.DefaultPinned,
		DBIndexedHint:      definition.DBIndexedHint,
		Provenance:         rowProvenance,
		Unit:               "",
		DefinitionRev:      definition.DefinitionRev,
		LifecycleState:     string(definition.Lifecycle),
		DefaultDisplayUnit: definition.DefaultDisplayUnit,
		UnitsJSON:          unitsJSON,
		CreatedAt:          now,
		UpdatedAt:          now,
	}
	if definition.Unit != nil {
		row.Unit = *definition.Unit
	}
	if existing != nil {
		row.SeedOwner = existing.SeedOwner
		row.SeedVersion = existing.SeedVersion
		row.SeedSourceVersion = existing.SeedSourceVersion
		row.CreatedAt = existing.CreatedAt
	}
	return row, nil
}

// encodeUnitsJSON은 units_json 열의 canonical 인코딩을 만든다. 빈 슬라이스는
// 빈 문자열로 인코딩해 decodeUnitsJSON과 왕복 일치한다.
func encodeUnitsJSON(units []domainentry.PropertyUnit) (string, error) {
	if len(units) == 0 {
		return "", nil
	}
	entries := make([]unitsJSONEntry, 0, len(units))
	for _, unit := range units {
		entries = append(entries, unitsJSONEntry{
			Code: unit.Code, Label: unit.Label, FactorToCanonical: unit.FactorToCanonical,
		})
	}
	encoded, err := json.Marshal(entries)
	if err != nil {
		return "", err
	}
	return string(encoded), nil
}
