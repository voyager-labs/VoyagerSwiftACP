package sqlite

import (
	"context"
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
// assignment를 읽는다: headers, values, active definitions, options. 이후
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
	defQuery := db.Where("workspace_id = ? AND lifecycle_state = ?", wsBytes, "active")
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
