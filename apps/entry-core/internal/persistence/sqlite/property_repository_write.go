package sqlite

// VOY-765 property assignment의 tx-scoped write 원시 함수다. 저장소 진입점은
// Store.WithinTx로 이 파일의 함수들을 호출하고, todo 7의 원자적 변경 서비스는
// 같은 트랜잭션 안에서 이 함수들을 직접 조합한다.

import (
	"strings"
	"time"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

func WriteEntryPropertyAssignments(
	tx *gorm.DB,
	wsctx domainentry.WorkspaceContext,
	facts []domainentry.EntryPropertyAssignment,
) error {
	if wsctx.ID == (domainentry.WorkspaceID{}) {
		return ErrInvalidPropertyRow
	}
	if len(facts) == 0 {
		return nil
	}
	seen := make(map[EntryPropertyRef]struct{}, len(facts))
	propertyIDs := make([]domainentry.PropertyID, 0, len(facts))
	propertySeen := make(map[domainentry.PropertyID]struct{}, len(facts))
	for _, fact := range facts {
		ref := EntryPropertyRef{EntryID: fact.EntryID, PropertyID: fact.PropertyID}
		if _, duplicate := seen[ref]; duplicate {
			return ErrDuplicateAssignmentRef
		}
		seen[ref] = struct{}{}
		if fact.WorkspaceID != wsctx.ID {
			return ErrEntryPropertyWorkspaceMismatch
		}
		if _, ok := propertySeen[fact.PropertyID]; !ok {
			propertySeen[fact.PropertyID] = struct{}{}
			propertyIDs = append(propertyIDs, fact.PropertyID)
		}
	}

	contracts, err := loadWriteContracts(tx, wsctx, propertyIDs)
	if err != nil {
		return err
	}
	validated := make([]domainentry.EntryPropertyAssignment, 0, len(facts))
	for _, fact := range facts {
		contract, ok := contracts[fact.PropertyID]
		if !ok {
			return ErrEntryPropertyDefinitionMissing
		}
		validFact, err := domainentry.NewEntryPropertyAssignment(fact, contract)
		if err != nil {
			return err
		}
		validated = append(validated, validFact)
	}
	return persistEntryPropertyAssignments(tx, wsctx, validated)
}

// DeleteEntryPropertyAssignments는 header 행을 삭제하고 cascade로 값 행을
// 함께 제거한다.
func DeleteEntryPropertyAssignments(
	tx *gorm.DB,
	wsctx domainentry.WorkspaceContext,
	refs []EntryPropertyRef,
) error {
	if wsctx.ID == (domainentry.WorkspaceID{}) {
		return ErrInvalidPropertyRow
	}
	if len(refs) == 0 {
		return nil
	}
	conds := make([]string, 0, len(refs))
	args := make([]interface{}, 0, 1+2*len(refs))
	args = append(args, wsctx.ID.Bytes())
	for _, ref := range refs {
		if !validEntryIDShape(ref.EntryID) {
			return ErrInvalidPropertyRow
		}
		conds = append(conds, "(entry_id = ? AND property_id = ?)")
		args = append(args, ref.EntryID, ref.PropertyID.Bytes())
	}
	query := "workspace_id = ? AND (" + strings.Join(conds, " OR ") + ")"
	return tx.Where(query, args...).Delete(&EntryPropertyAssignmentRow{}).Error
}

// loadWriteContracts는 대상 정의들과 active 선택지를 두 개의 batched 질의로
// 읽어 쓰기용 계약표를 만든다. 누락/tombstoned 정의는 호출자에게
// ErrEntryPropertyDefinitionMissing으로 보고된다.
func loadWriteContracts(
	tx *gorm.DB,
	wsctx domainentry.WorkspaceContext,
	propertyIDs []domainentry.PropertyID,
) (map[domainentry.PropertyID]domainentry.AssignmentContract, error) {
	wsBytes := wsctx.ID.Bytes()
	filter := propertyIDFilter(propertyIDs)

	var defRows []WorkspacePropertyDefinitionRow
	defQuery := tx.Where("workspace_id = ? AND lifecycle_state = ?", wsBytes, "active")
	if filter != "" {
		defQuery = defQuery.Where(filter, idFilterArg(propertyIDs))
	}
	if err := defQuery.Find(&defRows).Error; err != nil {
		return nil, err
	}
	if len(defRows) != len(propertyIDs) {
		return nil, ErrEntryPropertyDefinitionMissing
	}

	var optionRows []WorkspacePropertyOptionRow
	optionQuery := tx.Where("workspace_id = ? AND active = ?", wsBytes, true)
	if filter != "" {
		optionQuery = optionQuery.Where(filter, idFilterArg(propertyIDs))
	}
	if err := optionQuery.Find(&optionRows).Error; err != nil {
		return nil, err
	}

	optionsByProperty := make(map[string][]WorkspacePropertyOptionRow, len(defRows))
	for _, option := range optionRows {
		key := string(option.PropertyID)
		optionsByProperty[key] = append(optionsByProperty[key], option)
	}
	contracts := make(map[domainentry.PropertyID]domainentry.AssignmentContract, len(defRows))
	for _, def := range defRows {
		contract, err := assignmentContractFor(def, optionsByProperty[string(def.PropertyID)], true)
		if err != nil {
			return nil, err
		}
		id, err := parsePropertyIDBlob(def.PropertyID)
		if err != nil {
			return nil, err
		}
		contracts[id] = contract
	}
	return contracts, nil
}

// persistEntryPropertyAssignments는 검증된 fact들을 header upsert + 값 행
// 교체로 기록한다. header와 값은 같은 tx 안에서 함께 적용되므로 부분 상태가
// 남지 않는다.
func persistEntryPropertyAssignments(
	tx *gorm.DB,
	wsctx domainentry.WorkspaceContext,
	facts []domainentry.EntryPropertyAssignment,
) error {
	now := tx.NowFunc()
	headerRows := make([]EntryPropertyAssignmentRow, 0, len(facts))
	valueRows := make([]EntryPropertyAssignmentValueRow, 0, len(facts))
	for _, fact := range facts {
		headerRows = append(headerRows, EntryPropertyAssignmentRow{
			WorkspaceID:           fact.WorkspaceID.Bytes(),
			EntryID:               fact.EntryID,
			PropertyID:            fact.PropertyID.Bytes(),
			TargetKind:            string(fact.TargetKind),
			State:                 string(fact.State),
			RecordRevision:        int(fact.RecordRevision),
			ValueContractRevision: int(fact.ValueContractRevision),
			CreatedAt:             now,
			UpdatedAt:             now,
		})
		if fact.Scalar != nil {
			row := baseValueRow(fact, 0, now)
			if err := fillAssignmentValueColumns(&row, *fact.Scalar); err != nil {
				return err
			}
			valueRows = append(valueRows, row)
		}
		for _, member := range fact.Many {
			row := baseValueRow(fact, member.Ordinal, now)
			if err := fillAssignmentValueColumns(&row, member.Value); err != nil {
				return err
			}
			valueRows = append(valueRows, row)
		}
	}

	if err := tx.Clauses(clause.OnConflict{
		Columns: []clause.Column{
			{Name: "workspace_id"}, {Name: "entry_id"}, {Name: "property_id"},
		},
		DoUpdates: clause.AssignmentColumns([]string{
			"target_kind", "state", "record_revision", "value_contract_revision", "updated_at",
		}),
	}).Create(&headerRows).Error; err != nil {
		return err
	}

	// 값 행은 전면 교체한다: 기존 자식 행만 지우고 새 자식 행을 넣는다. header는
	// upsert되므로 지우지 않는다(지우면 cascade와 FK 위반의 원인이 된다).
	if err := deleteEntryPropertyValues(tx, wsctx, refsOf(facts)); err != nil {
		return err
	}
	if len(valueRows) == 0 {
		return nil
	}
	return tx.Create(&valueRows).Error
}

// deleteEntryPropertyValues는 참조 집합의 값 행만 삭제한다.
func deleteEntryPropertyValues(tx *gorm.DB, wsctx domainentry.WorkspaceContext, refs []EntryPropertyRef) error {
	if len(refs) == 0 {
		return nil
	}
	conds := make([]string, 0, len(refs))
	args := make([]interface{}, 0, 1+2*len(refs))
	args = append(args, wsctx.ID.Bytes())
	for _, ref := range refs {
		conds = append(conds, "(entry_id = ? AND property_id = ?)")
		args = append(args, ref.EntryID, ref.PropertyID.Bytes())
	}
	query := "workspace_id = ? AND (" + strings.Join(conds, " OR ") + ")"
	return tx.Where(query, args...).Delete(&EntryPropertyAssignmentValueRow{}).Error
}

// assembleEntryPropertyAssignments는 네 family의 행을 domain fact 사전으로
// 조립한다. header 없는 값 행, active 정의 없는 header, 상태-불일치 payload는
// 모두 실패 닫기하며 요청 유무와 무관하게 orphan은 건너뛰지 않는다.
func baseValueRow(fact domainentry.EntryPropertyAssignment, ordinal int, now time.Time) EntryPropertyAssignmentValueRow {
	return EntryPropertyAssignmentValueRow{
		WorkspaceID: fact.WorkspaceID.Bytes(),
		EntryID:     fact.EntryID,
		PropertyID:  fact.PropertyID.Bytes(),
		Ordinal:     ordinal,
		CreatedAt:   now,
		UpdatedAt:   now,
	}
}

func refsOf(facts []domainentry.EntryPropertyAssignment) []EntryPropertyRef {
	refs := make([]EntryPropertyRef, 0, len(facts))
	for _, fact := range facts {
		refs = append(refs, EntryPropertyRef{EntryID: fact.EntryID, PropertyID: fact.PropertyID})
	}
	return refs
}
