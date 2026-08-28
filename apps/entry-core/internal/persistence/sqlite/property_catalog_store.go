package sqlite

import (
	"context"
	"errors"
	"time"

	"gorm.io/gorm"

	applicationproperty "github.com/voyager-labs/voyager-app/apps/entry-core/internal/application/property"
	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// 이 파일은 VOY-765 todo 10에서 도입한 application property 포트의 production
// SQLite 구현이다. 데몬 조합(cmd/entry-core-daemon)이 CatalogService와
// ChangeService를 구성하려면 property.CatalogRepository 포트의 실구현이 필요했지만
// 어느 패키지에도 존재하지 않았다. tx 스코프 해석(txScopeKey)이 필요한 저장소
// 계층 소유 코드이므로 이 패키지에 최소 seam으로 추가한다(패키지 소유 규칙상
// persistence 매핑은 sqlite가 소유한다). 행 매핑은 기존 mapper와 row 타입만
// 재사용한다.

// PropertyCatalogStore는 applicationproperty.CatalogRepository 포트의 SQLite
// 구현이다. 인스턴스는 데몬이 주입한 단일 워크스페이스로 스코핑되며, 읽기는
// 비활성(tombstoned) 행도 포함해 과거 assignment 해석을 보존하고, 쓰기는 물리
// 삭제 없이 create/update만 수행한다.
type PropertyCatalogStore struct {
	store     *Store
	workspace domainentry.WorkspaceContext
}

// NewPropertyCatalogStore는 store를 워크스페이스 컨텍스트에 바인딩해 포트 구현을
// 만든다. 워크스페이스 식별은 반드시 typed UUIDv7이어야 한다.
func NewPropertyCatalogStore(store *Store, workspace domainentry.WorkspaceContext) (*PropertyCatalogStore, error) {
	if store == nil || applicationproperty.ValidateWorkspaceContext(workspace) != nil {
		return nil, applicationproperty.ErrWorkspaceRequired
	}
	return &PropertyCatalogStore{store: store, workspace: workspace}, nil
}

// session은 ctx에 tx 스코프가 있으면 그 트랜잭션을, 없으면 공유 커넥션을
// 돌려준다. TransactionRunner가 붙인 tx 안에서의 읽기·쓰기가 같은 트랜잭션에
// 참여하기 위한 단일 진입점이다.
func (s *PropertyCatalogStore) session(ctx context.Context) (*gorm.DB, error) {
	if applicationproperty.ValidateWorkspaceContext(s.workspace) != nil {
		return nil, applicationproperty.ErrWorkspaceRequired
	}
	if scope, ok := ctx.Value(txScopeKey{}).(*txScope); ok && scope != nil && scope.tx != nil {
		return scope.tx.WithContext(ctx), nil
	}
	return s.store.db.WithContext(ctx), nil
}

// requireWorkspace는 읽기 메서드 인자의 워크스페이스가 바인딩된 것과 일치하는지
// 검사한다. 불일치는 실패 닫기다.
func (s *PropertyCatalogStore) requireWorkspace(workspace domainentry.WorkspaceContext) error {
	if workspace.ID != s.workspace.ID {
		return applicationproperty.ErrWorkspaceRequired
	}
	return nil
}

// Definition은 정의 한 행을 돌려준다. tombstoned 행도 조회되며, 없으면
// applicationproperty.ErrDefinitionNotFound다.
func (s *PropertyCatalogStore) Definition(ctx context.Context, workspace domainentry.WorkspaceContext, propertyID domainentry.PropertyID) (domainentry.WorkspacePropertyDefinition, error) {
	if err := s.requireWorkspace(workspace); err != nil {
		return domainentry.WorkspacePropertyDefinition{}, err
	}
	db, err := s.session(ctx)
	if err != nil {
		return domainentry.WorkspacePropertyDefinition{}, err
	}
	var row WorkspacePropertyDefinitionRow
	queryErr := db.Where(
		"workspace_id = ? AND property_id = ?", workspace.ID.Bytes(), propertyID.Bytes(),
	).First(&row).Error
	if errors.Is(queryErr, gorm.ErrRecordNotFound) {
		return domainentry.WorkspacePropertyDefinition{}, applicationproperty.ErrDefinitionNotFound
	}
	if queryErr != nil {
		return domainentry.WorkspacePropertyDefinition{}, queryErr
	}
	return mapDefinitionRow(row)
}

// DefinitionByKey는 (workspace, namespace, canonical_key) exact 조회다.
// idx_def_ns_key UNIQUE 인덱스를 타므로 mutation 트랜잭션 안의 생성 중복 검사가
// 워크스페이스 전체 스캔이 되지 않는다. tombstoned 행도 유일성 판정에 포함된다.
func (s *PropertyCatalogStore) DefinitionByKey(
	ctx context.Context,
	workspace domainentry.WorkspaceContext,
	namespace, canonicalKey string,
) (domainentry.WorkspacePropertyDefinition, error) {
	if err := s.requireWorkspace(workspace); err != nil {
		return domainentry.WorkspacePropertyDefinition{}, err
	}
	db, err := s.session(ctx)
	if err != nil {
		return domainentry.WorkspacePropertyDefinition{}, err
	}
	var row WorkspacePropertyDefinitionRow
	queryErr := db.Where(
		"workspace_id = ? AND namespace = ? AND canonical_key = ?",
		workspace.ID.Bytes(), namespace, canonicalKey,
	).First(&row).Error
	if errors.Is(queryErr, gorm.ErrRecordNotFound) {
		return domainentry.WorkspacePropertyDefinition{}, applicationproperty.ErrDefinitionNotFound
	}
	if queryErr != nil {
		return domainentry.WorkspacePropertyDefinition{}, queryErr
	}
	return mapDefinitionRow(row)
}

// Definitions은 워크스페이스의 모든 정의를 (namespace, canonical_key) 순으로
// 돌려준다. 비활성 행도 과거 assignment read-back을 위해 포함한다.
func (s *PropertyCatalogStore) Definitions(ctx context.Context, workspace domainentry.WorkspaceContext) ([]domainentry.WorkspacePropertyDefinition, error) {
	if err := s.requireWorkspace(workspace); err != nil {
		return nil, err
	}
	db, err := s.session(ctx)
	if err != nil {
		return nil, err
	}
	var rows []WorkspacePropertyDefinitionRow
	if err := db.Where("workspace_id = ?", workspace.ID.Bytes()).
		Order("namespace ASC, canonical_key ASC").Find(&rows).Error; err != nil {
		return nil, err
	}
	definitions := make([]domainentry.WorkspacePropertyDefinition, 0, len(rows))
	for _, row := range rows {
		definition, mapErr := mapDefinitionRow(row)
		if mapErr != nil {
			return nil, mapErr
		}
		definitions = append(definitions, definition)
	}
	return definitions, nil
}

// Option은 선택지 한 행을 돌려준다. 비활성 행도 조회되며, 없으면
// applicationproperty.ErrOptionNotFound다.
func (s *PropertyCatalogStore) Option(ctx context.Context, workspace domainentry.WorkspaceContext, optionID domainentry.PropertyOptionID) (domainentry.PropertyOption, error) {
	if err := s.requireWorkspace(workspace); err != nil {
		return domainentry.PropertyOption{}, err
	}
	db, err := s.session(ctx)
	if err != nil {
		return domainentry.PropertyOption{}, err
	}
	var row WorkspacePropertyOptionRow
	queryErr := db.Where(
		"workspace_id = ? AND option_id = ?", workspace.ID.Bytes(), optionID.Bytes(),
	).First(&row).Error
	if errors.Is(queryErr, gorm.ErrRecordNotFound) {
		return domainentry.PropertyOption{}, applicationproperty.ErrOptionNotFound
	}
	if queryErr != nil {
		return domainentry.PropertyOption{}, queryErr
	}
	return mapOptionRow(row)
}

// Options은 정의의 모든 선택지를 ordinal 오름차순으로 돌려준다. 비활성 행도
// 포함한다.
func (s *PropertyCatalogStore) Options(ctx context.Context, workspace domainentry.WorkspaceContext, propertyID domainentry.PropertyID) ([]domainentry.PropertyOption, error) {
	if err := s.requireWorkspace(workspace); err != nil {
		return nil, err
	}
	db, err := s.session(ctx)
	if err != nil {
		return nil, err
	}
	var rows []WorkspacePropertyOptionRow
	if err := db.Where(
		"workspace_id = ? AND property_id = ?", workspace.ID.Bytes(), propertyID.Bytes(),
	).Order("ordinal ASC").Find(&rows).Error; err != nil {
		return nil, err
	}
	options := make([]domainentry.PropertyOption, 0, len(rows))
	for _, row := range rows {
		option, mapErr := mapOptionRow(row)
		if mapErr != nil {
			return nil, mapErr
		}
		options = append(options, option)
	}
	return options, nil
}

// mapOptionRow는 선택지 행을 domain 값으로 매핑한다. ID BLOB은 typed parser로만
// 검증하며 잘못된 행은 실패 닫기한다.
func mapOptionRow(row WorkspacePropertyOptionRow) (domainentry.PropertyOption, error) {
	propertyID, err := parsePropertyIDBlob(row.PropertyID)
	if err != nil {
		return domainentry.PropertyOption{}, err
	}
	if len(row.OptionID) != len(domainentry.PropertyOptionID{}) {
		return domainentry.PropertyOption{}, ErrInvalidCatalogBLOB
	}
	var optionID domainentry.PropertyOptionID
	copy(optionID[:], row.OptionID)
	if _, err := domainentry.ParsePropertyOptionID(optionID.String()); err != nil {
		return domainentry.PropertyOption{}, ErrInvalidCatalogBLOB
	}
	option := domainentry.PropertyOption{
		OptionID: optionID, PropertyID: propertyID, Label: row.Label,
		Color: row.Color, Ordinal: row.Ordinal, Active: row.Active,
	}
	if err := option.Validate(); err != nil {
		return domainentry.PropertyOption{}, ErrInvalidCatalogRow
	}
	return option, nil
}

// optionToRow는 domain 선택지를 GORM 행으로 매핑한다.
func optionToRow(option domainentry.PropertyOption, workspace []byte, now time.Time) (WorkspacePropertyOptionRow, error) {
	if err := option.Validate(); err != nil {
		return WorkspacePropertyOptionRow{}, ErrInvalidCatalogRow
	}
	return WorkspacePropertyOptionRow{
		WorkspaceID: workspace,
		OptionID:    option.OptionID.Bytes(),
		PropertyID:  option.PropertyID.Bytes(),
		Label:       option.Label,
		Color:       option.Color,
		Ordinal:     option.Ordinal,
		Active:      option.Active,
		CreatedAt:   now,
		UpdatedAt:   now,
	}, nil
}

// DefinitionsPage는 definition.list의 저장소 단계 페이징이다. property_id
// 오름차순으로 after 이후 limit+1행만 읽어 has_more과 다음 커서를 계산한다.
// page_size 적용 전의 전체 적재를 차단한다.
func (s *PropertyCatalogStore) DefinitionsPage(
	ctx context.Context,
	workspace domainentry.WorkspaceContext,
	activeOnly bool,
	idFilter []domainentry.PropertyID,
	after *domainentry.PropertyID,
	limit int,
) ([]domainentry.WorkspacePropertyDefinition, *domainentry.PropertyID, bool, error) {
	if err := s.requireWorkspace(workspace); err != nil {
		return nil, nil, false, err
	}
	db, err := s.session(ctx)
	if err != nil {
		return nil, nil, false, err
	}
	wsBytes := workspace.ID.Bytes()
	query := db.Where("workspace_id = ?", wsBytes)
	if activeOnly {
		query = query.Where("lifecycle_state = ?", "active")
	}
	if len(idFilter) > 0 {
		args := make([]interface{}, 0, len(idFilter))
		for _, id := range idFilter {
			args = append(args, id.Bytes())
		}
		query = query.Where("property_id IN ?", args)
	}
	if after != nil {
		query = query.Where("property_id > ?", after.Bytes())
	}
	var rows []WorkspacePropertyDefinitionRow
	if err := query.Order("property_id ASC").Limit(limit + 1).Find(&rows).Error; err != nil {
		return nil, nil, false, err
	}
	hasMore := len(rows) > limit
	if hasMore {
		rows = rows[:limit]
	}
	definitions := make([]domainentry.WorkspacePropertyDefinition, 0, len(rows))
	var next *domainentry.PropertyID
	for _, row := range rows {
		definition, mapErr := mapDefinitionRow(row)
		if mapErr != nil {
			return nil, nil, false, mapErr
		}
		definitions = append(definitions, definition)
		id := definition.PropertyID
		next = &id
	}
	return definitions, next, hasMore, nil
}

// OptionsForDefinitions은 페이지 정의들의 선택지를 단일 IN 쿼리로 읽어
// property별 ordinal 오름차순 목록으로 묶는다.
func (s *PropertyCatalogStore) OptionsForDefinitions(
	ctx context.Context,
	workspace domainentry.WorkspaceContext,
	propertyIDs []domainentry.PropertyID,
) (map[domainentry.PropertyID][]domainentry.PropertyOption, error) {
	result := make(map[domainentry.PropertyID][]domainentry.PropertyOption, len(propertyIDs))
	if len(propertyIDs) == 0 {
		return result, nil
	}
	if err := s.requireWorkspace(workspace); err != nil {
		return nil, err
	}
	db, err := s.session(ctx)
	if err != nil {
		return nil, err
	}
	args := make([]interface{}, 0, len(propertyIDs))
	for _, id := range propertyIDs {
		args = append(args, id.Bytes())
	}
	var rows []WorkspacePropertyOptionRow
	if err := db.Where("workspace_id = ?", workspace.ID.Bytes()).Where("property_id IN ?", args).
		Order("property_id ASC, ordinal ASC").Find(&rows).Error; err != nil {
		return nil, err
	}
	for _, row := range rows {
		propertyID, err := parsePropertyIDBlob(row.PropertyID)
		if err != nil {
			return nil, err
		}
		option, err := mapOptionRow(row)
		if err != nil {
			return nil, err
		}
		result[propertyID] = append(result[propertyID], option)
	}
	return result, nil
}


// DefinitionsPageSnapshot은 definition.list의 단일 읽기 스냅샷 결합 조회다.
// 정의 페이지와 해당 옵션을 하나의 read 트랜잭션 안에서 읽어 조립한다 — 분리
// 조회 사이에 option mutation이 커밋되면 새 label/order/state가 이전 definition
// revision과 함께 응답에 실려 클라이언트 CAS가 즉시 conflict가 된다.
// tx 스코프 ctx로 호출되면 기존 트랜잭션에 참여한다.
func (s *PropertyCatalogStore) DefinitionsPageSnapshot(
	ctx context.Context,
	activeOnly bool,
	idFilter []domainentry.PropertyID,
	after *domainentry.PropertyID,
	limit int,
) ([]applicationproperty.DefinitionView, *domainentry.PropertyID, bool, error) {
	var views []applicationproperty.DefinitionView
	var next *domainentry.PropertyID
	var hasMore bool
	wrapErr := s.store.WithinTx(ctx, func(tx *gorm.DB) error {
		// tx 스코프 ctx로 기존 조회 메서드들이 같은 트랜잭션에서 읽게 한다.
		txScopeCtx := s.store.WithTxScope(ctx, tx)
		definitions, pageNext, pageHasMore, err := s.DefinitionsPage(txScopeCtx, s.workspace, activeOnly, idFilter, after, limit)
		if err != nil {
			return err
		}
		propertyIDs := make([]domainentry.PropertyID, 0, len(definitions))
		for _, definition := range definitions {
			propertyIDs = append(propertyIDs, definition.PropertyID)
		}
		optionsByProperty, err := s.OptionsForDefinitions(txScopeCtx, s.workspace, propertyIDs)
		if err != nil {
			return err
		}
		views = make([]applicationproperty.DefinitionView, 0, len(definitions))
		for _, definition := range definitions {
			views = append(views, applicationproperty.DefinitionView{Definition: definition, Options: optionsByProperty[definition.PropertyID]})
		}
		next, hasMore = pageNext, pageHasMore
		return nil
	})
	if wrapErr != nil {
		return nil, nil, false, wrapErr
	}
	return views, next, hasMore, nil
}
