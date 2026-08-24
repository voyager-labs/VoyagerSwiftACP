-- Reverse of 0006_catalog_seed_marker. Never executed at runtime; exists for
-- ADR-014 artifact-format compliance.
ALTER TABLE workspace_metadata DROP COLUMN catalog_seed_ordinal;
ALTER TABLE workspace_metadata DROP COLUMN catalog_seed_source_version;
