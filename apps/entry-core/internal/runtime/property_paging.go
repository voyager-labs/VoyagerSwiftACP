package runtime

import (
	"sort"

	applicationproperty "github.com/voyager-labs/voyager-app/apps/entry-core/internal/application/property"
	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/protocol/schema"
)

// Property 목록 페이지네이션은 dispatch 계층 소유다. application은 전체 bounded
// 목록을 돌려주고 wire의 page_size·page_token·has_more 계약은 여기서 완성한다.
// 토큰은 마지막 반환 행의 property_id 텍스트로, 정렬 키는 property_id 오름차순
// 단일 기준이다. 토큰은 인증 커서가 아니라 어드바이저리 커서다(todo-3 동결).

// pageDefinitionViews는 정의 뷰를 정렬·필터링하고 요청 창으로 잘라 반환한다.
func pageDefinitionViews(views []applicationproperty.DefinitionView, params *schema.PropertyDefinitionListParams) ([]schema.PropertyDefinition, *string, bool) {
	filtered := make([]applicationproperty.DefinitionView, 0, len(views))
	for _, view := range views {
		if len(params.RequestedPropertyIDs) > 0 && !containsText(params.RequestedPropertyIDs, view.Definition.PropertyID.String()) {
			continue
		}
		if !params.IncludeDisabled && !view.IsActive() {
			continue
		}
		filtered = append(filtered, view)
	}
	sort.Slice(filtered, func(left, right int) bool {
		return filtered[left].Definition.PropertyID.String() < filtered[right].Definition.PropertyID.String()
	})
	start := 0
	if params.PageToken != nil {
		start = firstIndexAfterText(filtered, func(view applicationproperty.DefinitionView) string { return view.Definition.PropertyID.String() }, *params.PageToken)
	}
	end := start + params.PageSize
	if end > len(filtered) {
		end = len(filtered)
	}
	definitions := make([]schema.PropertyDefinition, 0, end-start)
	for _, view := range filtered[start:end] {
		definition, code := applicationproperty.DefinitionViewToWire(view)
		if code != "" {
			return nil, nil, false
		}
		definitions = append(definitions, definition)
	}
	hasMore := end < len(filtered)
	var nextToken *string
	if hasMore && len(definitions) > 0 {
		token := definitions[len(definitions)-1].PropertyID
		nextToken = &token
	}
	return definitions, nextToken, hasMore
}

// pageAssignmentFacts는 fact 목록(PropertyID 오름차순 계약)을 필터링하고 창으로
// 자른다. 사상 실패는 실패 닫기로 페이지 전체를 거절한다.
func pageAssignmentFacts(facts []domainentry.EntryPropertyAssignment, definitions map[domainentry.PropertyID]applicationproperty.DefinitionView, params *schema.PropertyAssignmentListParams) ([]schema.PropertyAssignment, *string, bool) {
	filtered := make([]domainentry.EntryPropertyAssignment, 0, len(facts))
	for _, fact := range facts {
		if len(params.RequestedPropertyIDs) > 0 && !containsText(params.RequestedPropertyIDs, fact.PropertyID.String()) {
			continue
		}
		filtered = append(filtered, fact)
	}
	sort.Slice(filtered, func(left, right int) bool {
		return filtered[left].PropertyID.String() < filtered[right].PropertyID.String()
	})
	start := 0
	if params.PageToken != nil {
		start = firstIndexAfterText(filtered, func(fact domainentry.EntryPropertyAssignment) string { return fact.PropertyID.String() }, *params.PageToken)
	}
	end := start + params.PageSize
	if end > len(filtered) {
		end = len(filtered)
	}
	assignments := make([]schema.PropertyAssignment, 0, end-start)
	for _, fact := range filtered[start:end] {
		mapped, code := assignmentFactToWire(fact, definitions)
		if code != "" {
			return nil, nil, false
		}
		assignments = append(assignments, mapped)
	}
	hasMore := end < len(filtered)
	var nextToken *string
	if hasMore && len(assignments) > 0 {
		token := assignments[len(assignments)-1].PropertyID
		nextToken = &token
	}
	return assignments, nextToken, hasMore
}

func containsText(values []string, target string) bool {
	for _, value := range values {
		if value == target {
			return true
		}
	}
	return false
}

// firstIndexAfterText는 정렬된 목록에서 토큰보다 큰 첫 키 위치를 돌려준다.
func firstIndexAfterText[T any](items []T, key func(T) string, token string) int {
	return sort.Search(len(items), func(index int) bool { return key(items[index]) > token })
}
