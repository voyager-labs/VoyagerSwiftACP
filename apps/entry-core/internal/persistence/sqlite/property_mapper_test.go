package sqlite

// structural-completeness Gate 1: row struct의 모든 필드가 매핑 대상으로
// 명시적으로 계정되어야 한다. 새 필드 추가는 이 테스트를 실패시키고 작성자의
// 의식적 갱신을 강제한다(침묵하는 누락 방지).

import (
	"reflect"
	"strings"
	"testing"
)

// propertyRowColumnCoverage는 테이블별로 매핑이 담당하는 컬럼과 그 용도를
// 나열한다. 이 지도가 mapper/repo 구현과 lockstep을 이룬다.
var propertyRowColumnCoverage = map[string]map[string]string{
	"workspace_property_options": {
		"workspace_id": "identity blob, refOfRow/contract 검증",
		"option_id":    "identity blob, contract 옵션 수집",
		"property_id":  "소유 정의 참조, contract 옵션 수집",
		"label":        "저장 전용 메타데이터, 매핑 변환 없음",
		"color":        "저장 전용 메타데이터, 매핑 변환 없음",
		"ordinal":      "옵션 순서, 저장 전용",
		"active":       "쓰기 계약 active 필터/read-back 보존 분기",
		"created_at":   "저장 전용 타임스탬프",
		"updated_at":   "저장 전용 타임스탬프",
	},
	"entry_property_assignments": {
		"workspace_id":            "identity blob, refOfRow/cross-workspace 거절",
		"entry_id":                "identity text, validEntryIDShape/domain 검증",
		"property_id":             "identity blob, 정의 계약 lookup",
		"target_kind":             "assignmentTargetKindForRow 판별 매핑",
		"state":                   "assignmentStateForRow 판별 매핑",
		"record_revision":         "domain RecordRevision 매핑",
		"value_contract_revision": "domain ValueContractRevision 매핑",
		"created_at":              "저장 전용 타임스탬프",
		"updated_at":              "upsert 갱신 대상 타임스탬프",
	},
	"entry_property_assignment_values": {
		"workspace_id":    "identity blob, refOfRow",
		"entry_id":        "identity text, validEntryIDShape",
		"property_id":     "identity blob, refOfRow",
		"ordinal":         "ordered-many 위치, assembleOneAssignment 연속성 검증 입력",
		"value_kind":      "assignmentValueFromRow/fillAssignmentValueColumns 판별 매핑",
		"boolean_value":   "AssignmentValue.Boolean payload",
		"decimal_value":   "AssignmentValue.Decimal payload",
		"date_value":      "AssignmentValue.Date payload",
		"timestamp_value": "AssignmentValue.Timestamp payload",
		"text_value":      "AssignmentValue.Text payload",
		"option_id":       "AssignmentValue.OptionID payload",
		"created_at":      "저장 전용 타임스탬프",
		"updated_at":      "저장 전용 타임스탬프",
	},
}

func TestPropertyRowColumnCoverage(t *testing.T) {
	rows := []struct {
		table string
		model interface{}
	}{
		{"workspace_property_options", WorkspacePropertyOptionRow{}},
		{"entry_property_assignments", EntryPropertyAssignmentRow{}},
		{"entry_property_assignment_values", EntryPropertyAssignmentValueRow{}},
	}
	for _, row := range rows {
		covered := propertyRowColumnCoverage[row.table]
		if covered == nil {
			t.Fatalf("table %s has no coverage map entry", row.table)
		}
		typ := reflect.TypeOf(row.model)
		for i := 0; i < typ.NumField(); i++ {
			tag := typ.Field(i).Tag.Get("gorm")
			column := gormColumnName(tag)
			if column == "" {
				t.Fatalf("%s.%s has no gorm column tag", row.table, typ.Field(i).Name)
			}
			if _, ok := covered[column]; !ok {
				t.Fatalf("column %q of %s is neither mapped nor explicitly excluded; update propertyRowColumnCoverage with the mapping decision", column, row.table)
			}
			delete(covered, column)
		}
		if len(covered) > 0 {
			t.Fatalf("table %s coverage map names unknown columns: %v", row.table, keysOf(covered))
		}
	}
}

func gormColumnName(tag string) string {
	for _, part := range strings.Split(tag, ";") {
		if value, ok := strings.CutPrefix(part, "column:"); ok {
			return value
		}
	}
	return ""
}

func keysOf(m map[string]string) []string {
	out := make([]string, 0, len(m))
	for key := range m {
		out = append(out, key)
	}
	return out
}
