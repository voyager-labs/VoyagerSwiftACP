package sqlite

import "time"

// WorkspaceMetadataRow is the single-row workspace identity record. It maps
// 1:1 to migration 0001_workspace_metadata (table `workspace_metadata`). The
// `singleton` primary key is constrained to the literal value 1 so the table
// can hold exactly one row. No embedded gorm.Model: every column, type, and
// nullability is declared explicitly so the Atlas loader's generated schema
// matches the hand-written migration byte-for-byte.
//
// This slice creates no tables; the type is declared here only as the input
// for the Task 4 Atlas loader and the Task 5 workspace bootstrap.
type WorkspaceMetadataRow struct {
	// Singleton is the fixed primary key value 1 (CHECK singleton = 1).
	Singleton int `gorm:"primaryKey;column:singleton;type:integer;not null;default:1;check:singleton = 1"`

	// WorkspaceID is the 16-byte UUIDv7 blob (CHECK length(workspace_id) = 16).
	WorkspaceID []byte `gorm:"column:workspace_id;type:blob;not null;uniqueIndex:uni_workspace_metadata_workspace_id;check:length(workspace_id) = 16"`

	// CreatedAt and UpdatedAt are auto-maintained by GORM on insert/update.
	CreatedAt time.Time `gorm:"column:created_at;type:datetime;not null"`
	UpdatedAt time.Time `gorm:"column:updated_at;type:datetime;not null"`
}

// TableName returns the canonical table name.
func (WorkspaceMetadataRow) TableName() string {
	return "workspace_metadata"
}
