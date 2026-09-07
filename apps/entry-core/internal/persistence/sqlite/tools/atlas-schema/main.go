// Command atlas-schema is the Atlas GORM Provider loader for the Entry Core
// SQLite schema. It is a dev/CI-only tool (never imported by daemon code): Atlas
// runs it via `go run ./internal/persistence/sqlite/tools/atlas-schema` and
// reads the desired schema DDL from stdout. Every persistence model is
// registered explicitly here (ADR-014 rule 2); nothing is auto-discovered.
package main

import (
	"fmt"
	"io"
	"os"

	"ariga.io/atlas-provider-gorm/gormschema"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/persistence/sqlite"
)

func main() {
	stmts, err := gormschema.New("sqlite").Load(
		&sqlite.WorkspaceMetadataRow{},
		&sqlite.WorkspacePropertyDefinitionRow{},
		&sqlite.SourcePropertyDescriptorRow{},
		&sqlite.PropertyBindingRow{},
		&sqlite.WorkspacePropertyTermRow{},
		&sqlite.WorkspacePropertyOptionRow{},
		&sqlite.EntryPropertyAssignmentRow{},
		&sqlite.EntryPropertyAssignmentValueRow{},
	)
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to load gorm schema: %v\n", err)
		os.Exit(1)
	}
	if _, err := io.WriteString(os.Stdout, stmts); err != nil {
		fmt.Fprintf(os.Stderr, "failed to write schema: %v\n", err)
		os.Exit(1)
	}
}
