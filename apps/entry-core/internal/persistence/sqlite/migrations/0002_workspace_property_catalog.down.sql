-- reverse: create unique index "idx_term_value" to workspace_property_terms
DROP INDEX `idx_term_value`;

-- reverse: create "workspace_property_terms" table
DROP TABLE `workspace_property_terms`;

-- reverse: create "property_bindings" table
DROP TABLE `property_bindings`;

-- reverse: create "source_property_descriptors" table
DROP TABLE `source_property_descriptors`;

-- reverse: create unique index "idx_def_ns_key" to workspace_property_definitions
DROP INDEX `idx_def_ns_key`;

-- reverse: create "workspace_property_definitions" table
DROP TABLE `workspace_property_definitions`;

-- reverse: add unique index "workspace_id" to workspace_metadata
DROP INDEX `uni_workspace_metadata_workspace_id`;
