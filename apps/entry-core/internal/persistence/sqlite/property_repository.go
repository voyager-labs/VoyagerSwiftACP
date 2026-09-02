package sqlite

import (
	"context"
	applicationproperty "github.com/voyager-labs/voyager-app/apps/entry-core/internal/application/property"
	"strings"

	"gorm.io/gorm"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// EntryPropertyRef는 assignment의 durable 자연 키 중 워크스페이스를 제외한
// (entry_id, property_id) 축이다. 저장소 API는 워크스페이스를 별도 인자로
// 받아 모든 질의와 쓰기가 한 워크스페이스로 스코핑된다.
type EntryPropertyRef struct {
	EntryID    string
	PropertyID domainentry.PropertyID
}

// EntryPropertyRepository는 entry property assignment의 batched read와
// transactional write를 소유한다. 읽기는 고정 쿼리 예산(4 queries)으로
// 동작하고, 쓰기는 반드시 Store.WithinTx 안에서 tx-scoped *gorm.DB로
// 실행된다.
type EntryPropertyRepository struct {
	store *Store
}

// NewEntryPropertyRepository returns a repository bound to the store.
func NewEntryPropertyRepository(store *Store) *EntryPropertyRepository {
	return &EntryPropertyRepository{store: store}
}

// LoadAssignments는 요청한 (entry, property) 집합을 고정 4-쿼리 예산으로 읽어
// domain fact 사전으로 반환한다. durable row가 없는 요청 키는 implicit unset
// revision 0으로 채워진다. corrupt row와 참조 고아는 실패 닫기한다.
//
// ctx에 Store.WithTxScope가 붙인 tx 스코프가 있으면 반드시 그 트랜잭션 안에서
// 읽는다. 스코프를 무시하면 열린 트랜잭션이 단일 커넥션 풀의 유일 연결을 점유한
// 상태에서 두 번째 연결을 기다리게 되어 교착한다(ChangeService.Execute의
// WithinTx 경계 안 읽기가 정확히 이 경로다).
func (r *EntryPropertyRepository) LoadAssignments(
	ctx context.Context,
	wsctx domainentry.WorkspaceContext,
	entryIDs []string,
	propertyIDs []domainentry.PropertyID,
) (map[EntryPropertyRef]domainentry.EntryPropertyAssignment, error) {
	db := r.store.db.WithContext(ctx)
	if scope, ok := ctx.Value(txScopeKey{}).(*txScope); ok && scope != nil && scope.tx != nil {
		db = scope.tx.WithContext(ctx)
	}
	return LoadEntryPropertyAssignments(db, wsctx, entryIDs, propertyIDs)
}

// LoadAssignmentsPage는 assignment.list의 저장소 단계 페이징이다. 자세한 계약은
// LoadEntryPropertyAssignmentsPage다.
func (r *EntryPropertyRepository) LoadAssignmentsPage(
	ctx context.Context,
	wsctx domainentry.WorkspaceContext,
	entryID string,
	requestedIDs []domainentry.PropertyID,
	after *domainentry.PropertyID,
	limit int,
) ([]domainentry.EntryPropertyAssignment, *domainentry.PropertyID, bool, error) {
	// 네 조회(header/value/정의/선택지)와 조립을 하나의 read snapshot 안에서
	// 수행한다. 연결마다 goroutine이 실행되므로 조회 사이에 execute가 커밋하면
	// 이전 revision의 header와 새 payload가 조합되어 잘못된 CAS 토큰이나
	// ErrAssignmentPayloadRequired internal_error가 만들어진다. tx 스코프 ctx로
	// 호출되면 기존 트랜잭션에 SAVEPOINT로 참여한다.
	var facts []domainentry.EntryPropertyAssignment
	var next *domainentry.PropertyID
	var hasMore bool
	wrapErr := r.store.WithinTx(ctx, func(tx *gorm.DB) error {
		var err error
		facts, next, hasMore, err = LoadEntryPropertyAssignmentsPage(tx, wsctx, entryID, requestedIDs, after, limit)
		return err
	})
	if wrapErr != nil {
		return nil, nil, false, wrapErr
	}
	return facts, next, hasMore, nil
}

// LoadAssignmentsCapped는 overlay 조회의 행 예산 버전이다. 자세한 계약은
// LoadEntryPropertyAssignmentsCapped다.
func (r *EntryPropertyRepository) LoadAssignmentsCapped(
	ctx context.Context,
	wsctx domainentry.WorkspaceContext,
	entryIDs []string,
	propertyIDs []domainentry.PropertyID,
	maxHeaders int,
) ([]domainentry.EntryPropertyAssignment, error) {
	db := r.store.db.WithContext(ctx)
	if scope, ok := ctx.Value(txScopeKey{}).(*txScope); ok && scope != nil && scope.tx != nil {
		db = scope.tx.WithContext(ctx)
	}
	return LoadEntryPropertyAssignmentsCapped(db, wsctx, entryIDs, propertyIDs, maxHeaders)
}

func (r *EntryPropertyRepository) LoadAssignmentsMemberCapped(ctx context.Context, wsctx domainentry.WorkspaceContext, entryIDs []string, propertyIDs []domainentry.PropertyID, maxMembers int) (map[EntryPropertyRef]domainentry.EntryPropertyAssignment, error) {
	db := r.store.db.WithContext(ctx)
	if scope, ok := ctx.Value(txScopeKey{}).(*txScope); ok && scope != nil && scope.tx != nil {
		db = scope.tx.WithContext(ctx)
	}
	if wsctx.ID == (domainentry.WorkspaceID{}) || maxMembers < 0 {
		return nil, ErrInvalidPropertyRow
	}
	wsBytes := wsctx.ID.Bytes()
	var headers []EntryPropertyAssignmentRow
	if err := scopeAssignmentQuery(db.Model(&EntryPropertyAssignmentRow{}), wsBytes, entryIDs, propertyIDs).Find(&headers).Error; err != nil {
		return nil, err
	}
	var values []EntryPropertyAssignmentValueRow
	if err := scopeAssignmentQuery(db.Model(&EntryPropertyAssignmentValueRow{}), wsBytes, entryIDs, propertyIDs).Order("entry_id, property_id, ordinal").Limit(maxMembers + 1).Find(&values).Error; err != nil {
		return nil, err
	}
	if len(values) > maxMembers {
		return nil, applicationproperty.ErrConditionQueryScopeTooLarge
	}
	filter := propertyIDFilter(propertyIDs)
	defQuery := db.Where("workspace_id = ?", wsBytes)
	optionQuery := db.Where("workspace_id = ?", wsBytes)
	if filter != "" {
		defQuery = defQuery.Where(filter, idFilterArg(propertyIDs))
		optionQuery = optionQuery.Where(filter, idFilterArg(propertyIDs))
	}
	var definitions []WorkspacePropertyDefinitionRow
	if err := defQuery.Find(&definitions).Error; err != nil {
		return nil, err
	}
	var options []WorkspacePropertyOptionRow
	if err := optionQuery.Find(&options).Error; err != nil {
		return nil, err
	}
	result, err := assembleEntryPropertyAssignments(headers, values, definitions, options)
	if err != nil {
		return nil, err
	}
	for _, entryID := range entryIDs {
		for _, propertyID := range propertyIDs {
			ref := EntryPropertyRef{EntryID: entryID, PropertyID: propertyID}
			if _, ok := result[ref]; !ok {
				result[ref] = domainentry.ImplicitUnsetEntryPropertyAssignment(wsctx.ID, entryID, propertyID)
			}
		}
	}
	return result, nil
}

// LoadAssignmentsByRefs는 exact-pair change 경로 읽기다. 자세한 계약은
// LoadEntryPropertyAssignmentsByRefs다.
func (r *EntryPropertyRepository) LoadAssignmentsByRefs(
	ctx context.Context,
	wsctx domainentry.WorkspaceContext,
	refs []EntryPropertyRef,
) (map[EntryPropertyRef]domainentry.EntryPropertyAssignment, error) {
	db := r.store.db.WithContext(ctx)
	if scope, ok := ctx.Value(txScopeKey{}).(*txScope); ok && scope != nil && scope.tx != nil {
		db = scope.tx.WithContext(ctx)
	}
	return LoadEntryPropertyAssignmentsByRefs(db, wsctx, refs)
}

// SaveAssignments는 fact 집합을 하나의 원자적 트랜잭션으로 upsert한다. 모든
// public mutation 진입점은 Store.WithinTx만 사용한다.
func (r *EntryPropertyRepository) SaveAssignments(
	ctx context.Context,
	wsctx domainentry.WorkspaceContext,
	facts []domainentry.EntryPropertyAssignment,
) error {
	return r.store.WithinTx(ctx, func(tx *gorm.DB) error {
		return WriteEntryPropertyAssignments(tx, wsctx, facts)
	})
}

// DeleteAssignments는 참조 집합의 durable row를 제거해 implicit unset으로
// 되돌린다. 값 행은 foreign key cascade로 함께 삭제된다.
func (r *EntryPropertyRepository) DeleteAssignments(
	ctx context.Context,
	wsctx domainentry.WorkspaceContext,
	refs []EntryPropertyRef,
) error {
	return r.store.WithinTx(ctx, func(tx *gorm.DB) error {
		return DeleteEntryPropertyAssignments(tx, wsctx, refs)
	})
}

// LoadEntryPropertyAssignments는 tx-scoped *gorm.DB에서 고정 4-쿼리 예산으로
// assignment를 읽는다: headers, values, definitions(비활성 포함), options. 이후
// todo 7/8이 같은 트랜잭션 안에서 조합할 수 있도록 패키지 수준으로 노출한다.
func LoadEntryPropertyAssignments(
	db *gorm.DB,
	wsctx domainentry.WorkspaceContext,
	entryIDs []string,
	propertyIDs []domainentry.PropertyID,
) (map[EntryPropertyRef]domainentry.EntryPropertyAssignment, error) {
	if wsctx.ID == (domainentry.WorkspaceID{}) {
		return nil, ErrInvalidPropertyRow
	}
	for _, entryID := range entryIDs {
		if !validEntryIDShape(entryID) {
			return nil, ErrInvalidPropertyRow
		}
	}
	wsBytes := wsctx.ID.Bytes()

	var headerRows []EntryPropertyAssignmentRow
	if err := scopeAssignmentQuery(db.Model(&EntryPropertyAssignmentRow{}), wsBytes, entryIDs, propertyIDs).
		Find(&headerRows).Error; err != nil {
		return nil, err
	}

	var valueRows []EntryPropertyAssignmentValueRow
	if err := scopeAssignmentQuery(db.Model(&EntryPropertyAssignmentValueRow{}), wsBytes, entryIDs, propertyIDs).
		Order("ordinal").Find(&valueRows).Error; err != nil {
		return nil, err
	}

	defFilter := propertyIDFilter(propertyIDs)
	var defRows []WorkspacePropertyDefinitionRow
	// 읽기 경로는 tombstoned 정의도 포함해 과거 assignment 해석을 보존한다.
	// disable이 기존 assignment read-back을 깨지 않게 하는 계약이며, 신규 쓰기의
	// active 검증은 loadWriteContracts가 소관이다.
	defQuery := db.Where("workspace_id = ?", wsBytes)
	if defFilter != "" {
		defQuery = defQuery.Where(defFilter, idFilterArg(propertyIDs))
	}
	if err := defQuery.Find(&defRows).Error; err != nil {
		return nil, err
	}

	var optionRows []WorkspacePropertyOptionRow
	optionQuery := db.Where("workspace_id = ?", wsBytes)
	if defFilter != "" {
		optionQuery = optionQuery.Where(defFilter, idFilterArg(propertyIDs))
	}
	if err := optionQuery.Find(&optionRows).Error; err != nil {
		return nil, err
	}

	result, err := assembleEntryPropertyAssignments(headerRows, valueRows, defRows, optionRows)
	if err != nil {
		return nil, err
	}
	// durable row가 없는 요청 키는 implicit unset revision 0으로 채운다.
	for _, entryID := range entryIDs {
		for _, propertyID := range propertyIDs {
			ref := EntryPropertyRef{EntryID: entryID, PropertyID: propertyID}
			if _, ok := result[ref]; !ok {
				result[ref] = domainentry.ImplicitUnsetEntryPropertyAssignment(wsctx.ID, entryID, propertyID)
			}
		}
	}
	return result, nil
}

// WriteEntryPropertyAssignments는 검증된 fact 집합을 tx 안에서 upsert한다:
// header ON CONFLICT 갱신 + 값 행 전면 교체. 정의 계약 검증은 도메인
// NewEntryPropertyAssignment로 위임하며 unknown/inactive 정의는 실패 닫기한다.
func assembleEntryPropertyAssignments(
	headerRows []EntryPropertyAssignmentRow,
	valueRows []EntryPropertyAssignmentValueRow,
	defRows []WorkspacePropertyDefinitionRow,
	optionRows []WorkspacePropertyOptionRow,
) (map[EntryPropertyRef]domainentry.EntryPropertyAssignment, error) {
	defByProperty := make(map[string]WorkspacePropertyDefinitionRow, len(defRows))
	for _, def := range defRows {
		defByProperty[string(def.PropertyID)] = def
	}
	optionsByProperty := make(map[string][]WorkspacePropertyOptionRow, len(optionRows))
	for _, option := range optionRows {
		key := string(option.PropertyID)
		optionsByProperty[key] = append(optionsByProperty[key], option)
	}

	valuesByKey := make(map[EntryPropertyRef][]EntryPropertyAssignmentValueRow, len(headerRows))
	for _, value := range valueRows {
		ref, err := refOfRow(value.WorkspaceID, value.EntryID, value.PropertyID)
		if err != nil {
			return nil, err
		}
		valuesByKey[ref] = append(valuesByKey[ref], value)
	}

	result := make(map[EntryPropertyRef]domainentry.EntryPropertyAssignment, len(headerRows))
	for _, header := range headerRows {
		ref, err := refOfRow(header.WorkspaceID, header.EntryID, header.PropertyID)
		if err != nil {
			return nil, err
		}
		def, ok := defByProperty[string(header.PropertyID)]
		if !ok {
			return nil, ErrEntryPropertyOrphanRef
		}
		contract, err := assignmentContractFor(def, optionsByProperty[string(header.PropertyID)], false)
		if err != nil {
			return nil, ErrInvalidPropertyRow
		}
		state, err := assignmentStateForRow(header.State)
		if err != nil {
			return nil, err
		}
		targetKind, err := assignmentTargetKindForRow(header.TargetKind)
		if err != nil {
			return nil, err
		}
		children := valuesByKey[ref]
		delete(valuesByKey, ref)
		fact, err := assembleOneAssignment(ref, header, state, targetKind, contract, children)
		if err != nil {
			return nil, err
		}
		result[ref] = fact
	}
	// 남은 값 행은 header 없는 고아다.
	for range valuesByKey {
		return nil, ErrEntryPropertyOrphanRef
	}
	return result, nil
}

// assembleOneAssignment는 header 한 건과 그 값 행들을 domain fact으로
// 재구성하고 도메인 상태 기계로 최종 검증한다.
func assembleOneAssignment(
	ref EntryPropertyRef,
	header EntryPropertyAssignmentRow,
	state domainentry.AssignmentState,
	targetKind domainentry.AssignmentTargetKind,
	contract domainentry.AssignmentContract,
	children []EntryPropertyAssignmentValueRow,
) (domainentry.EntryPropertyAssignment, error) {
	fact := domainentry.EntryPropertyAssignment{
		WorkspaceID:           workspaceIDFromBytes(header.WorkspaceID),
		EntryID:               ref.EntryID,
		PropertyID:            ref.PropertyID,
		TargetKind:            targetKind,
		State:                 state,
		RecordRevision:        domainentry.RecordRevision(header.RecordRevision),
		ValueContractRevision: domainentry.ValueContractRevision(header.ValueContractRevision),
	}
	if state != domainentry.AssignmentStateValue && len(children) > 0 {
		return domainentry.EntryPropertyAssignment{}, ErrInvalidPropertyRow
	}
	if state == domainentry.AssignmentStateValue {
		switch contract.Cardinality {
		case domainentry.PropertyCardinalityOne:
			if len(children) > 1 || (len(children) == 1 && children[0].Ordinal != 0) {
				return domainentry.EntryPropertyAssignment{}, ErrInvalidPropertyRow
			}
			if len(children) == 1 {
				scalar, err := assignmentValueFromRow(children[0])
				if err != nil {
					return domainentry.EntryPropertyAssignment{}, err
				}
				fact.Scalar = &scalar
			}
		case domainentry.PropertyCardinalityMany:
			// empty-many=value 상태는 자식 0행의 non-nil 슬라이스여야 한다.
			fact.Many = make([]domainentry.OrderedAssignmentValue, 0, len(children))
			for _, child := range children {
				value, err := assignmentValueFromRow(child)
				if err != nil {
					return domainentry.EntryPropertyAssignment{}, err
				}
				fact.Many = append(fact.Many, domainentry.OrderedAssignmentValue{Ordinal: child.Ordinal, Value: value})
			}
		default:
			return domainentry.EntryPropertyAssignment{}, ErrInvalidPropertyRow
		}
	}
	if err := fact.Validate(contract); err != nil {
		return domainentry.EntryPropertyAssignment{}, ErrInvalidPropertyRow
	}
	return fact, nil
}

// scopeAssignmentQuery는 workspace/entry/property 필터를 공통 적용한다.
func scopeAssignmentQuery(db *gorm.DB, wsBytes []byte, entryIDs []string, propertyIDs []domainentry.PropertyID) *gorm.DB {
	query := db.Where("workspace_id = ?", wsBytes)
	if len(entryIDs) > 0 {
		query = query.Where("entry_id IN ?", entryIDs)
	}
	if filter := propertyIDFilter(propertyIDs); filter != "" {
		query = query.Where(filter, idFilterArg(propertyIDs))
	}
	return query
}

// propertyIDFilter는 property_id IN (...) 절을 만든다. 빈 집합은 필터 없음
// (전체)을 뜻한다.
func propertyIDFilter(propertyIDs []domainentry.PropertyID) string {
	if len(propertyIDs) == 0 {
		return ""
	}
	return "property_id IN (?)"
}

// idFilterArg는 IN (?) 자리표시자 하나에 슬라이스 하나로 바인딩되는 단일 인자를
// 만든다. GORM은 슬라이드 인자 하나를 (?, ?, ...)로 확장한다.
func idFilterArg(propertyIDs []domainentry.PropertyID) interface{} {
	args := make([]interface{}, 0, len(propertyIDs))
	for _, id := range propertyIDs {
		args = append(args, id.Bytes())
	}
	return args
}

// validEntryIDShape는 저장 경계에서 entry_id 리터럴 형태(ent:+43자 base64url)를
// 1차 검증한다. 최종 권위는 도메인 Validate다.
func validEntryIDShape(entryID string) bool {
	return len(entryID) == 47 && strings.HasPrefix(entryID, "ent:")
}

// workspaceIDFromBytes는 16-byte BLOB을 typed WorkspaceID로 복사한다.
func workspaceIDFromBytes(raw []byte) domainentry.WorkspaceID {
	var id domainentry.WorkspaceID
	copy(id[:], raw)
	return id
}

func refOfRow(workspace []byte, entryID string, property []byte) (EntryPropertyRef, error) {
	if err := validateWorkspaceID(workspace); err != nil {
		return EntryPropertyRef{}, err
	}
	propertyID, err := parsePropertyIDBlob(property)
	if err != nil {
		return EntryPropertyRef{}, err
	}
	return EntryPropertyRef{EntryID: entryID, PropertyID: propertyID}, nil
}

// LoadEntryPropertyAssignmentsByRefs는 change 경로용 exact-pair 읽기다.
// entry IN × property IN의 교차 적재가 아니라 요청된 (entry_id, property_id)
// 쌍만 읽어 단일 연결 점유 시간을 요청 규모(≤256쌍)로 제한한다. 정의·선택지는
// 쌍의 property 집합으로만 필터링한다. overlay가 쓰는 LoadEntryPropertyAssignments는
// 교차 조회가 목적에 맞아 그대로 유지한다.
func LoadEntryPropertyAssignmentsByRefs(
	db *gorm.DB,
	wsctx domainentry.WorkspaceContext,
	refs []EntryPropertyRef,
) (map[EntryPropertyRef]domainentry.EntryPropertyAssignment, error) {
	if wsctx.ID == (domainentry.WorkspaceID{}) {
		return nil, ErrInvalidPropertyRow
	}
	if len(refs) == 0 {
		return map[EntryPropertyRef]domainentry.EntryPropertyAssignment{}, nil
	}
	seen := make(map[EntryPropertyRef]struct{}, len(refs))
	pairs := make([][]interface{}, 0, len(refs))
	propertySeen := make(map[domainentry.PropertyID]struct{}, len(refs))
	var propertyIDs []domainentry.PropertyID
	for _, ref := range refs {
		if !validEntryIDShape(ref.EntryID) {
			return nil, ErrInvalidPropertyRow
		}
		if _, duplicate := seen[ref]; duplicate {
			continue
		}
		seen[ref] = struct{}{}
		pairs = append(pairs, []interface{}{ref.EntryID, ref.PropertyID.Bytes()})
		if _, ok := propertySeen[ref.PropertyID]; !ok {
			propertySeen[ref.PropertyID] = struct{}{}
			propertyIDs = append(propertyIDs, ref.PropertyID)
		}
	}
	wsBytes := wsctx.ID.Bytes()
	pairScope := func(db *gorm.DB) *gorm.DB {
		return db.Where("workspace_id = ?", wsBytes).Where("(entry_id, property_id) IN ?", pairs)
	}

	var headerRows []EntryPropertyAssignmentRow
	if err := pairScope(db.Model(&EntryPropertyAssignmentRow{})).Find(&headerRows).Error; err != nil {
		return nil, err
	}
	var valueRows []EntryPropertyAssignmentValueRow
	if err := pairScope(db.Model(&EntryPropertyAssignmentValueRow{})).Order("ordinal").Find(&valueRows).Error; err != nil {
		return nil, err
	}

	var defRows []WorkspacePropertyDefinitionRow
	if err := db.Where("workspace_id = ?", wsBytes).Where(propertyIDFilter(propertyIDs), idFilterArg(propertyIDs)).
		Find(&defRows).Error; err != nil {
		return nil, err
	}
	var optionRows []WorkspacePropertyOptionRow
	if err := db.Where("workspace_id = ?", wsBytes).Where(propertyIDFilter(propertyIDs), idFilterArg(propertyIDs)).
		Find(&optionRows).Error; err != nil {
		return nil, err
	}

	result, err := assembleEntryPropertyAssignments(headerRows, valueRows, defRows, optionRows)
	if err != nil {
		return nil, err
	}
	// durable row가 없는 요청 키는 implicit unset revision 0으로 채운다.
	for _, ref := range refs {
		if _, ok := result[ref]; !ok {
			result[ref] = domainentry.ImplicitUnsetEntryPropertyAssignment(wsctx.ID, ref.EntryID, ref.PropertyID)
		}
	}
	return result, nil
}

// LoadEntryPropertyAssignmentsPage는 assignment.list의 저장소 단계 페이징이다.
// 단일 entry의 property_id 오름차순 창(after 이후 limit+1행)만 읽고, 값·정의·
// 선택지도 페이지 property에 한정해 조회한다. durable row가 없는 property는
// 결과에서 제외된다(implicit unset). next는 다음 페이지의 after 커서다.
func LoadEntryPropertyAssignmentsPage(
	db *gorm.DB,
	wsctx domainentry.WorkspaceContext,
	entryID string,
	requestedIDs []domainentry.PropertyID,
	after *domainentry.PropertyID,
	limit int,
) ([]domainentry.EntryPropertyAssignment, *domainentry.PropertyID, bool, error) {
	if wsctx.ID == (domainentry.WorkspaceID{}) {
		return nil, nil, false, ErrInvalidPropertyRow
	}
	if !validEntryIDShape(entryID) {
		return nil, nil, false, ErrInvalidPropertyRow
	}
	wsBytes := wsctx.ID.Bytes()
	headerQuery := db.Where("workspace_id = ? AND entry_id = ?", wsBytes, entryID)
	if len(requestedIDs) > 0 {
		headerQuery = headerQuery.Where(propertyIDFilter(requestedIDs), idFilterArg(requestedIDs))
	}
	if after != nil {
		headerQuery = headerQuery.Where("property_id > ?", after.Bytes())
	}
	var headerRows []EntryPropertyAssignmentRow
	if err := headerQuery.Order("property_id ASC").Limit(limit + 1).Find(&headerRows).Error; err != nil {
		return nil, nil, false, err
	}
	hasMore := len(headerRows) > limit
	if hasMore {
		headerRows = headerRows[:limit]
	}
	if len(headerRows) == 0 {
		return []domainentry.EntryPropertyAssignment{}, nil, false, nil
	}
	pageIDs := make([]domainentry.PropertyID, 0, len(headerRows))
	for _, header := range headerRows {
		id, err := parsePropertyIDBlob(header.PropertyID)
		if err != nil {
			return nil, nil, false, err
		}
		pageIDs = append(pageIDs, id)
	}

	var valueRows []EntryPropertyAssignmentValueRow
	if err := db.Where("workspace_id = ? AND entry_id = ?", wsBytes, entryID).
		Where(propertyIDFilter(pageIDs), idFilterArg(pageIDs)).
		Order("property_id ASC, ordinal ASC").Find(&valueRows).Error; err != nil {
		return nil, nil, false, err
	}
	var defRows []WorkspacePropertyDefinitionRow
	if err := db.Where("workspace_id = ?", wsBytes).Where(propertyIDFilter(pageIDs), idFilterArg(pageIDs)).
		Find(&defRows).Error; err != nil {
		return nil, nil, false, err
	}
	var optionRows []WorkspacePropertyOptionRow
	if err := db.Where("workspace_id = ?", wsBytes).Where(propertyIDFilter(pageIDs), idFilterArg(pageIDs)).
		Find(&optionRows).Error; err != nil {
		return nil, nil, false, err
	}

	result, err := assembleEntryPropertyAssignments(headerRows, valueRows, defRows, optionRows)
	if err != nil {
		return nil, nil, false, err
	}
	facts := make([]domainentry.EntryPropertyAssignment, 0, len(result))
	for _, id := range pageIDs {
		if fact, ok := result[EntryPropertyRef{EntryID: entryID, PropertyID: id}]; ok {
			facts = append(facts, fact)
		}
	}
	next := pageIDs[len(pageIDs)-1]
	return facts, &next, hasMore, nil
}

// maximumPropertyManyItems는 many 값의 멤버 상한이다(protocol maximumPropertyManyItems와 동일).
const maximumPropertyManyItems = 256

// LoadEntryPropertyAssignmentsCapped는 overlay 조회용 행 예산 버전이다. 헤더
// 행과 값 행이 각각 상한을 넘으면 적재 전에 ErrScopeTooLarge로 실패 닫기한다 —
// 256 entry × 256 property 교차가 65,536 header와 many value 수백만 행을
// 적재하는 것을 차단한다. durable row가 없는 property는 결과에서 제외된다.
func LoadEntryPropertyAssignmentsCapped(
	db *gorm.DB,
	wsctx domainentry.WorkspaceContext,
	entryIDs []string,
	propertyIDs []domainentry.PropertyID,
	maxHeaders int,
) ([]domainentry.EntryPropertyAssignment, error) {
	if wsctx.ID == (domainentry.WorkspaceID{}) {
		return nil, ErrInvalidPropertyRow
	}
	wsBytes := wsctx.ID.Bytes()
	scope := func(db *gorm.DB) *gorm.DB {
		query := db.Where("workspace_id = ?", wsBytes)
		if len(entryIDs) > 0 {
			query = query.Where("entry_id IN ?", entryIDs)
		}
		if filter := propertyIDFilter(propertyIDs); filter != "" {
			query = query.Where(filter, idFilterArg(propertyIDs))
		}
		return query
	}
	var headerRows []EntryPropertyAssignmentRow
	if err := scope(db.Model(&EntryPropertyAssignmentRow{})).Order("entry_id ASC, property_id ASC").
		Limit(maxHeaders + 1).Find(&headerRows).Error; err != nil {
		return nil, err
	}
	if len(headerRows) > maxHeaders {
		return nil, applicationproperty.ErrScopeTooLarge
	}
	var valueRows []EntryPropertyAssignmentValueRow
	if err := scope(db.Model(&EntryPropertyAssignmentValueRow{})).
		Order("entry_id ASC, property_id ASC, ordinal ASC").
		Limit(maxHeaders*maximumPropertyManyItems + 1).Find(&valueRows).Error; err != nil {
		return nil, err
	}
	if len(valueRows) > maxHeaders*maximumPropertyManyItems {
		return nil, applicationproperty.ErrScopeTooLarge
	}

	var defRows []WorkspacePropertyDefinitionRow
	if err := db.Where("workspace_id = ?", wsBytes).Where(propertyIDFilter(propertyIDs), idFilterArg(propertyIDs)).
		Find(&defRows).Error; err != nil {
		return nil, err
	}
	var optionRows []WorkspacePropertyOptionRow
	if err := db.Where("workspace_id = ?", wsBytes).Where(propertyIDFilter(propertyIDs), idFilterArg(propertyIDs)).
		Find(&optionRows).Error; err != nil {
		return nil, err
	}

	result, err := assembleEntryPropertyAssignments(headerRows, valueRows, defRows, optionRows)
	if err != nil {
		return nil, err
	}
	facts := make([]domainentry.EntryPropertyAssignment, 0, len(result))
	for _, fact := range result {
		if fact.RecordRevision == 0 {
			continue
		}
		facts = append(facts, fact)
	}
	return facts, nil
}
