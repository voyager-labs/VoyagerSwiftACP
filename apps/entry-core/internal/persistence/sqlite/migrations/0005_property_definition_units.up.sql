-- Add the reviewed display-unit contract to each Workspace Property definition:
-- default_display_unit and the canonical units conversion JSON. DEFAULT '' is
-- required because SQLite cannot ADD COLUMN NOT NULL without a default on a
-- table that may already hold seeded rows.
ALTER TABLE `workspace_property_definitions` ADD COLUMN `default_display_unit` text NOT NULL DEFAULT '';
ALTER TABLE `workspace_property_definitions` ADD COLUMN `units_json` text NOT NULL DEFAULT '';
