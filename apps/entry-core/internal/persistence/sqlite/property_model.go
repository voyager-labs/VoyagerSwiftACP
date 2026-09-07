package sqlite

import "time"

// 이 파일은 0007_entry_properties 마이그레이션 체인의 세 GORM row 타입을
// 선언한다. catalog_model.go와 마찬가지로 의도적 속성(column/type/nullability)
// 을 전부 명시해 Atlas 로더의 desired schema가 hand-written 마이그레이션과
// 일치하도록 한다. 임베디드 gorm.Model은 쓰지 않는다. cross-table foreign
// key(composite 참조와 워크스페이스 소유 체인)는 Atlas 태그로 표현할 수
// 없어 0007 SQL에 hand-written으로 존재하며 TestPropertySchemaConstraints의
// PRAGMA 검사와 schema-parity allowlist가 그 대응을 증명한다.
//
// 이 타입들은 테이블을 만들지 않는다. Atlas GORM Provider 로더
// (tools/atlas-schema)와 VOY-765 property 저장소 계층의 입력일 뿐이다.

// WorkspacePropertyOptionRow는 select 정의의 워크스페이스 범위 선택지다.
// Identity는 (workspace_id, option_id)이고, (workspace_id, property_id,
// ordinal)은 정의별 선택지 순서의 유일 키다. Option value는 label이 아니라
// PropertyOptionID로 참조되며, 비활성(disabled) 선택지도 기존 assignment
// read-back 보존을 위해 행이 유지된다.
type WorkspacePropertyOptionRow struct {
	WorkspaceID []byte `gorm:"column:workspace_id;type:blob;not null;check:length(workspace_id) = 16;primaryKey;uniqueIndex:idx_option_property_ordinal"`
	OptionID    []byte `gorm:"column:option_id;type:blob;not null;check:length(option_id) = 16;primaryKey"`
	PropertyID  []byte `gorm:"column:property_id;type:blob;not null;check:length(property_id) = 16;uniqueIndex:idx_option_property_ordinal"`

	Label   string `gorm:"column:label;type:text;not null;check:length(label) >= 1"`
	Color   string `gorm:"column:color;type:text;not null;check:length(color) <= 64"`
	Ordinal int    `gorm:"column:ordinal;type:integer;not null;check:ordinal >= 0;uniqueIndex:idx_option_property_ordinal"`
	Active  bool   `gorm:"column:active;type:boolean;not null"`

	CreatedAt time.Time `gorm:"column:created_at;type:datetime;not null"`
	UpdatedAt time.Time `gorm:"column:updated_at;type:datetime;not null"`
}

// TableName returns the canonical table name.
func (WorkspacePropertyOptionRow) TableName() string {
	return "workspace_property_options"
}

// EntryPropertyAssignmentRow는 (workspace_id, entry_id, property_id) 자연 키의
// local authoritative assignment header다. surrogate ID는 없다. state는
// unset|null|value 상태 기계를 저장하고 revision은 항상 1 이상이다(revision 0은
// 저장되지 않은 implicit unset뿐이다). 값 payload는 값 테이블의 자식 행으로
// 저장되며 empty-many=value 상태(자식 0행)도 허용된다.
type EntryPropertyAssignmentRow struct {
	WorkspaceID []byte `gorm:"column:workspace_id;type:blob;not null;check:length(workspace_id) = 16;primaryKey"`
	EntryID     string `gorm:"column:entry_id;type:text;not null;check:length(entry_id) = 47 AND entry_id LIKE 'ent:%';primaryKey"`
	PropertyID  []byte `gorm:"column:property_id;type:blob;not null;check:length(property_id) = 16;primaryKey"`

	TargetKind string `gorm:"column:target_kind;type:text;not null;check:target_kind in ('core_native','locator_derived')"`
	State      string `gorm:"column:state;type:text;not null;check:state in ('unset','null','value')"`

	RecordRevision        int `gorm:"column:record_revision;type:integer;not null;check:record_revision >= 1"`
	ValueContractRevision int `gorm:"column:value_contract_revision;type:integer;not null;check:value_contract_revision >= 1"`

	CreatedAt time.Time `gorm:"column:created_at;type:datetime;not null"`
	UpdatedAt time.Time `gorm:"column:updated_at;type:datetime;not null"`
}

// TableName returns the canonical table name.
func (EntryPropertyAssignmentRow) TableName() string {
	return "entry_property_assignments"
}

// EntryPropertyAssignmentValueRow는 ordered assignment 값 멤버 하나다.
// Identity는 (workspace_id, entry_id, property_id, ordinal)이고 ordinal은
// 0부터 연속 증가한다(연속성은 저장소 매퍼가 실패 닫기 검증한다). 값 종류는
// value_kind 판별 컬럼과 정확히 하나의 typed payload 컬럼 조합으로 저장되며
// serialized JSON blob은 쓰지 않는다.
type EntryPropertyAssignmentValueRow struct {
	WorkspaceID []byte `gorm:"column:workspace_id;type:blob;not null;check:length(workspace_id) = 16;primaryKey"`
	EntryID     string `gorm:"column:entry_id;type:text;not null;check:length(entry_id) = 47 AND entry_id LIKE 'ent:%';primaryKey"`
	PropertyID  []byte `gorm:"column:property_id;type:blob;not null;check:length(property_id) = 16;primaryKey"`
	Ordinal     int    `gorm:"column:ordinal;type:integer;not null;check:ordinal >= 0;primaryKey"`

	ValueKind string `gorm:"column:value_kind;type:text;not null;check:(value_kind = 'boolean' AND boolean_value IS NOT NULL AND decimal_value IS NULL AND date_value IS NULL AND timestamp_value IS NULL AND text_value IS NULL AND option_id IS NULL) OR (value_kind = 'decimal' AND boolean_value IS NULL AND decimal_value IS NOT NULL AND date_value IS NULL AND timestamp_value IS NULL AND text_value IS NULL AND option_id IS NULL) OR (value_kind = 'date' AND boolean_value IS NULL AND decimal_value IS NULL AND date_value IS NOT NULL AND timestamp_value IS NULL AND text_value IS NULL AND option_id IS NULL) OR (value_kind = 'timestamp' AND boolean_value IS NULL AND decimal_value IS NULL AND date_value IS NULL AND timestamp_value IS NOT NULL AND text_value IS NULL AND option_id IS NULL) OR (value_kind = 'text' AND boolean_value IS NULL AND decimal_value IS NULL AND date_value IS NULL AND timestamp_value IS NULL AND text_value IS NOT NULL AND option_id IS NULL) OR (value_kind = 'option_ref' AND boolean_value IS NULL AND decimal_value IS NULL AND date_value IS NULL AND timestamp_value IS NULL AND text_value IS NULL AND option_id IS NOT NULL)"`

	BooleanValue   *bool   `gorm:"column:boolean_value;type:boolean"`
	DecimalValue   *string `gorm:"column:decimal_value;type:text"`
	DateValue      *string `gorm:"column:date_value;type:text"`
	TimestampValue *string `gorm:"column:timestamp_value;type:text"`
	TextValue      *string `gorm:"column:text_value;type:text"`
	OptionID       []byte  `gorm:"column:option_id;type:blob;check:(option_id IS NULL OR length(option_id) = 16)"`

	CreatedAt time.Time `gorm:"column:created_at;type:datetime;not null"`
	UpdatedAt time.Time `gorm:"column:updated_at;type:datetime;not null"`
}

// TableName returns the canonical table name.
func (EntryPropertyAssignmentValueRow) TableName() string {
	return "entry_property_assignment_values"
}
