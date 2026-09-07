-- Seed-applied marker columns on workspace_metadata. Written atomically by
-- ApplyCatalogSeed in the same transaction as the seed itself; NULL means the
-- seed has never been applied under this marker scheme.
ALTER TABLE workspace_metadata ADD COLUMN catalog_seed_ordinal integer NULL;
ALTER TABLE workspace_metadata ADD COLUMN catalog_seed_source_version text NULL;
