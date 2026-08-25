package runtime

// Property 목록 페이지네이션 테스트다. 토큰·has_more 파생과 필터 조합을 소유한다.

import (
	"context"
	"testing"

	applicationproperty "github.com/voyager-labs/voyager-app/apps/entry-core/internal/application/property"
	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/protocol/schema"
)

// TestPropertyPaginationWindows는 정의·할당 목록의 페이지 창을 증명한다. 토큰은
// 마지막 반환 property_id다. include_disabled와 requested_property_ids 필터,
// has_more/next_page_token 파생, 소진 페이지를 함께 잠근다.
func TestPropertyPaginationWindows(t *testing.T) {
	activeFirst := testDefinitionView(testPropertyID, true)
	disabledSecond := testDefinitionView(testPropertyID2, false)

	walk := func(includeDisabled bool, pageSize int, requested []string) []schema.PropertyDefinitionListResult {
		service := newRecordingPropertyService()
		service.listDefinitions = []applicationproperty.DefinitionView{activeFirst, disabledSecond}
		runtime := newPropertyRuntime(service)
		var pages []schema.PropertyDefinitionListResult
		var token *string
		for {
			request := schema.Request{RequestID: "id", Method: schema.MethodPropertyDefinitionList, PropertyDefinitionListParams: &schema.PropertyDefinitionListParams{PageSize: pageSize, RequestedPropertyIDs: requested, IncludeDisabled: includeDisabled, PageToken: token}}
			response := runtime.Dispatch(context.Background(), request)
			if !response.OK {
				t.Fatalf("page response=%#v", response)
			}
			result := response.Result.(schema.PropertyDefinitionListResult)
			pages = append(pages, result)
			if result.NextPageToken == nil {
				break
			}
			token = result.NextPageToken
			if len(pages) > 10 {
				t.Fatal("pagination did not terminate")
			}
		}
		return pages
	}

	allPages := walk(true, 1, []string{})
	if len(allPages) != 2 || len(allPages[0].Definitions) != 1 || allPages[0].Definitions[0].PropertyID != testPropertyID || !allPages[0].HasMore || len(allPages[1].Definitions) != 1 || allPages[1].HasMore {
		t.Fatalf("walk pages=%+v", allPages)
	}
	activeOnly := walk(false, 8, []string{})
	if len(activeOnly) != 1 || len(activeOnly[0].Definitions) != 1 || activeOnly[0].Definitions[0].PropertyID != testPropertyID || activeOnly[0].HasMore {
		t.Fatalf("active only pages=%+v", activeOnly)
	}
	filtered := walk(true, 8, []string{testPropertyID2})
	if len(filtered) != 1 || len(filtered[0].Definitions) != 1 || filtered[0].Definitions[0].PropertyID != testPropertyID2 {
		t.Fatalf("filtered pages=%+v", filtered)
	}

	assignmentService := newRecordingPropertyService()
	assignmentService.listDefinitions = []applicationproperty.DefinitionView{testDefinitionView(testPropertyID, true), testDefinitionView(testPropertyID2, true)}
	propertyID := domainentry.MustPropertyID(testPropertyID)
	propertyID2 := domainentry.MustPropertyID(testPropertyID2)
	entryID := testEntryID()
	assignmentService.facts = []domainentry.EntryPropertyAssignment{
		{EntryID: entryID, PropertyID: propertyID, State: domainentry.AssignmentStateNull, RecordRevision: 1, ValueContractRevision: 1},
		{EntryID: entryID, PropertyID: propertyID2, State: domainentry.AssignmentStateNull, RecordRevision: 1, ValueContractRevision: 1},
	}
	runtime := newPropertyRuntime(assignmentService)
	first := schema.Request{RequestID: "id", Method: schema.MethodPropertyAssignmentList, PropertyAssignmentListParams: &schema.PropertyAssignmentListParams{PageSize: 1, RequestedPropertyIDs: []string{}, Target: localPathTarget("/a")}}
	firstResponse := runtime.Dispatch(context.Background(), first)
	if !firstResponse.OK {
		t.Fatalf("assignment page=%#v", firstResponse)
	}
	firstResult := firstResponse.Result.(schema.PropertyAssignmentListResult)
	if len(firstResult.Assignments) != 1 || firstResult.Assignments[0].PropertyID != testPropertyID || !firstResult.HasMore || firstResult.NextPageToken == nil {
		t.Fatalf("assignment first page=%+v", firstResult)
	}
	second := first
	second.RequestID = "id2"
	second.PropertyAssignmentListParams.PageToken = firstResult.NextPageToken
	secondResponse := runtime.Dispatch(context.Background(), second)
	secondResult := secondResponse.Result.(schema.PropertyAssignmentListResult)
	if len(secondResult.Assignments) != 1 || secondResult.Assignments[0].PropertyID != testPropertyID2 || secondResult.HasMore || secondResult.NextPageToken != nil {
		t.Fatalf("assignment second page=%+v", secondResult)
	}
}
