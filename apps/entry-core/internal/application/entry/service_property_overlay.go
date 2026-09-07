package entry

import (
	"context"
	"encoding/hex"
	"sort"
	"strings"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// parseWorkspaceIDText는 하이픈 UUID 텍스트를 typed WorkspaceID로 파싱한다.
// 도메인은 바이트 파서만 노출하므로 텍스트 정규화는 application 경계에서 수행한다.
func parseWorkspaceIDText(text string) (domainentry.WorkspaceID, error) {
	raw, err := hex.DecodeString(strings.ReplaceAll(text, "-", ""))
	if err != nil {
		return domainentry.WorkspaceID{}, err
	}
	return domainentry.ParseWorkspaceID(raw)
}

// errPropertyOverlayFailed는 overlay 계약의 실패 닫기 오류를 만든다.
func errPropertyOverlayFailed() error {
	return newApplicationError("property_overlay_failed", "property_overlay_failed", ErrPropertyOverlayFailed)
}

// applyPropertyOverlay는 읽기 결과에 batched Property overlay를 정확히 한 번의
// loader 호출로 병합한다. loader 미주입·빈 요청·빈 결과·비(非)UUIDv7 워크스페이스는
// no-op으로 기존 동작을 유지하고, 로드·검증·병합 실패는 요청 전체를 실패 닫기한다.
func (service *UnifiedService) applyPropertyOverlay(ctx context.Context, workspaceID string, entries []CanonicalEntry, requestedProperties []string, definitions map[string]domainentry.PropertyDefinition) error {
	if service.propertyOverlay == nil || len(requestedProperties) == 0 || len(entries) == 0 {
		return nil
	}
	workspace, parseErr := parseWorkspaceIDText(workspaceID)
	if parseErr != nil {
		return nil
	}
	entryIDs := make([]string, 0, len(entries))
	for _, entry := range entries {
		entryIDs = append(entryIDs, entry.EntryRef.EntryID)
	}
	propertyIDs := requestedPropertyIDs(definitions)
	rows, loadErr := service.propertyOverlay.LoadOverlay(ctx, domainentry.WorkspaceContext{ID: workspace}, entryIDs, propertyIDs)
	if loadErr != nil {
		return errPropertyOverlayFailed()
	}
	return mergePropertyOverlayRows(entries, rows, propertyIDs)
}

// requestedPropertyIDs는 해석된 정의 맵에서 요청 PropertyID를 중복 없이
// PropertyID 오름차순으로 모은다. 맵 순회가 비결정적이므로 정렬해 고정한다.
func requestedPropertyIDs(definitions map[string]domainentry.PropertyDefinition) []domainentry.PropertyID {
	seen := make(map[domainentry.PropertyID]struct{}, len(definitions))
	ids := make([]domainentry.PropertyID, 0, len(definitions))
	for _, definition := range definitions {
		if _, exists := seen[definition.PropertyID]; exists {
			continue
		}
		seen[definition.PropertyID] = struct{}{}
		ids = append(ids, definition.PropertyID)
	}
	sort.Slice(ids, func(left, right int) bool { return ids[left].String() < ids[right].String() })
	return ids
}

// mergePropertyOverlayRows는 overlay 행을 결과 순서 그대로 병합한다. 알 수 없는
// Entry 키, 행 불일치, 미요청 Property, 중복 행, 소스 소유 충돌, 스냅샷 재구성
// 실패는 모두 실패 닫기하며 소스 필드를 부분 노출하지 않는다.
func mergePropertyOverlayRows(entries []CanonicalEntry, rows map[string][]domainentry.PropertyValue, requestedIDs []domainentry.PropertyID) error {
	if len(rows) == 0 {
		return nil
	}
	knownEntries := make(map[string]struct{}, len(entries))
	for _, entry := range entries {
		knownEntries[entry.EntryRef.EntryID] = struct{}{}
	}
	for entryID := range rows {
		if _, exists := knownEntries[entryID]; !exists {
			return errPropertyOverlayFailed()
		}
	}
	requestedSet := make(map[domainentry.PropertyID]struct{}, len(requestedIDs))
	for _, id := range requestedIDs {
		requestedSet[id] = struct{}{}
	}
	for index, entry := range entries {
		overlay := rows[entry.EntryRef.EntryID]
		if len(overlay) == 0 {
			continue
		}
		if err := validateOverlayRows(entry, overlay, requestedSet); err != nil {
			return err
		}
		merged := append(
			make([]domainentry.PropertyValue, 0, len(entry.EntrySnapshot.CanonicalProperties)+len(overlay)),
			entry.EntrySnapshot.CanonicalProperties...)
		merged = append(merged, overlay...)
		snapshot, snapshotErr := domainentry.NewCanonicalEntrySnapshot(
			entry.EntryRef, entry.EntrySnapshot.DisplayName, entry.EntrySnapshot.ParentRef,
			sortCanonicalProperties(merged), entry.EntrySnapshot.SourceRevision, entry.EntrySnapshot.ObservedRevision,
			entry.EntrySnapshot.ObservedAt, entry.EntrySnapshot.CanonicalModifiedAt,
			entry.EntrySnapshot.Availability, entry.EntrySnapshot.Freshness,
		)
		if snapshotErr != nil {
			return errPropertyOverlayFailed()
		}
		entries[index] = CanonicalEntry{EntryRef: entry.EntryRef, EntrySnapshot: snapshot, AccessContext: entry.AccessContext}
	}
	return nil
}

// validateOverlayRows는 overlay 행 각각이 대상 Entry 사실과 요청 범위와 일치하는지
// 검사한다. 소스가 이미 소유한 PropertyID와의 충돌도 실패 닫기한다.
func validateOverlayRows(entry CanonicalEntry, overlay []domainentry.PropertyValue, requestedSet map[domainentry.PropertyID]struct{}) error {
	sourceOwned := make(map[domainentry.PropertyID]struct{}, len(entry.EntrySnapshot.CanonicalProperties))
	for _, property := range entry.EntrySnapshot.CanonicalProperties {
		sourceOwned[property.PropertyID] = struct{}{}
	}
	seen := make(map[domainentry.PropertyID]struct{}, len(overlay))
	for _, row := range overlay {
		if row.EntryID != entry.EntryRef.EntryID {
			return errPropertyOverlayFailed()
		}
		if _, requested := requestedSet[row.PropertyID]; !requested {
			return errPropertyOverlayFailed()
		}
		if _, duplicate := seen[row.PropertyID]; duplicate {
			return errPropertyOverlayFailed()
		}
		if _, conflict := sourceOwned[row.PropertyID]; conflict {
			return errPropertyOverlayFailed()
		}
		seen[row.PropertyID] = struct{}{}
	}
	return nil
}
