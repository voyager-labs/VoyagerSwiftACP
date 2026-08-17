# Atlas project configuration for the Entry Core SQLite schema.
#
# The desired schema is produced by the GORM Provider loader in
# internal/persistence/sqlite/tools/atlas-schema (see that package for the
# model registration contract, ADR-014 rule 2). Migrations are formatted for
# golang-migrate and live in internal/persistence/sqlite/migrations.
#
# Generation (run from apps/entry-core, via the pinned mise tool `atlas`):
#   mise exec -- atlas migrate diff <name> --env gorm
#   mise exec -- atlas migrate hash --env gorm
data "external_schema" "gorm" {
  program = [
    "go",
    "run",
    "./internal/persistence/sqlite/tools/atlas-schema",
  ]
}

env "gorm" {
  src = data.external_schema.gorm.url
  dev = "sqlite://dev?mode=memory&cache=shared"

  migration {
    dir = "file://internal/persistence/sqlite/migrations"
  }

  format {
    migrate {
      diff = "{{ sql . \"  \" }}"
    }
  }
}
