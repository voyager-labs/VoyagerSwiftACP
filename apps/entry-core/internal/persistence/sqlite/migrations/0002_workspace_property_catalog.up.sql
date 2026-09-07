-- add unique index "workspace_id" to workspace_metadata so catalog tables can
-- reference the workspace identity column with a foreign key
CREATE UNIQUE INDEX `uni_workspace_metadata_workspace_id` ON `workspace_metadata`(`workspace_id`);

-- create "workspace_property_definitions" table
CREATE TABLE `workspace_property_definitions` (
  `workspace_id` blob NOT NULL,
  `property_id` blob NOT NULL,
  `origin` text NOT NULL,
  `identity_scheme` text NOT NULL,
  `namespace` text NOT NULL,
  `canonical_key` text NOT NULL,
  `display_name` text NOT NULL,
  `description` text NOT NULL,
  `value_type` text NOT NULL,
  `cardinality` text NOT NULL,
  `nullable` boolean NOT NULL,
  `editable` boolean NOT NULL,
  `default_hidden` boolean NOT NULL,
  `default_pinned` boolean NOT NULL,
  `db_indexed_hint` boolean NOT NULL,
  `provenance` text NOT NULL,
  `unit` text NOT NULL,
  `definition_revision` integer NOT NULL,
  `lifecycle_state` text NOT NULL,
  `seed_owner` text,
  `seed_version` integer,
  `seed_source_version` text,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`workspace_id`,`property_id`),
  CONSTRAINT `fk_workspace_property_definitions_workspace` FOREIGN KEY (`workspace_id`) REFERENCES `workspace_metadata`(`workspace_id`),
  CONSTRAINT `chk_workspace_property_definitions_origin` CHECK (origin in ('built_in','user_defined')),
  CONSTRAINT `chk_workspace_property_definitions_value_type` CHECK (value_type in ('text','number','boolean','date','datetime','select')),
  CONSTRAINT `chk_workspace_property_definitions_lifecycle_state` CHECK (lifecycle_state in ('active','tombstoned')),
  CONSTRAINT `chk_workspace_property_definitions_property_id` CHECK (length(property_id) = 16),
  CONSTRAINT `chk_workspace_property_definitions_definition_revision` CHECK (definition_revision >= 0),
  CONSTRAINT `chk_workspace_property_definitions_identity_scheme` CHECK (identity_scheme in ('registry_derived','voyager_issued')),
  CONSTRAINT `chk_workspace_property_definitions_cardinality` CHECK (cardinality in ('one','many')),
  CONSTRAINT `chk_workspace_property_definitions_workspace_id` CHECK (length(workspace_id) = 16)
);

-- create unique index "idx_def_ns_key" to workspace_property_definitions
CREATE UNIQUE INDEX `idx_def_ns_key` ON `workspace_property_definitions`(`workspace_id`,`namespace`,`canonical_key`);

-- create "source_property_descriptors" table
CREATE TABLE `source_property_descriptors` (
  `workspace_id` blob NOT NULL,
  `provider_id` text NOT NULL,
  `source_instance_id` text NOT NULL,
  `scope_kind` text NOT NULL,
  `scope_external_id` text NOT NULL,
  `external_property_id` text NOT NULL,
  `authority_kind` text NOT NULL,
  `native_type` text NOT NULL,
  `native_cardinality` text NOT NULL,
  `source_readable` boolean NOT NULL,
  `source_queryable` boolean NOT NULL,
  `source_writable` boolean NOT NULL,
  `lifecycle_state` text NOT NULL,
  `availability_note` text NOT NULL,
  `seed_owner` text,
  `seed_version` integer,
  `seed_source_version` text,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`workspace_id`,`provider_id`,`source_instance_id`,`scope_kind`,`scope_external_id`,`external_property_id`),
  CONSTRAINT `fk_source_property_descriptors_workspace` FOREIGN KEY (`workspace_id`) REFERENCES `workspace_metadata`(`workspace_id`),
  CONSTRAINT `chk_source_property_descriptors_workspace_id` CHECK (length(workspace_id) = 16),
  CONSTRAINT `chk_source_property_descriptors_lifecycle_state` CHECK (lifecycle_state in ('active','tombstoned')),
  CONSTRAINT `chk_source_property_descriptors_authority_kind` CHECK (authority_kind in ('system','provider'))
);

-- create "property_bindings" table
CREATE TABLE `property_bindings` (
  `workspace_id` blob NOT NULL,
  `property_id` blob NOT NULL,
  `provider_id` text NOT NULL,
  `source_instance_id` text NOT NULL,
  `scope_kind` text NOT NULL,
  `scope_external_id` text NOT NULL,
  `external_property_id` text NOT NULL,
  `binding_ordinal` integer NOT NULL,
  `read_transform` text NOT NULL,
  `direction` text NOT NULL,
  `effective_readable` boolean NOT NULL,
  `effective_queryable` boolean NOT NULL,
  `effective_writable` boolean NOT NULL,
  `query_profile` text NOT NULL,
  `mapping_version` integer NOT NULL,
  `value_contract_revision` integer NOT NULL,
  `mapping_provenance` text NOT NULL,
  `approval_state` text NOT NULL,
  `lossiness` text NOT NULL,
  `lifecycle_state` text NOT NULL,
  `seed_owner` text,
  `seed_version` integer,
  `seed_source_version` text,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`workspace_id`,`property_id`,`provider_id`,`source_instance_id`,`scope_kind`,`scope_external_id`,`external_property_id`),
  CONSTRAINT `fk_property_bindings_workspace` FOREIGN KEY (`workspace_id`) REFERENCES `workspace_metadata`(`workspace_id`),
  CONSTRAINT `fk_property_bindings_definition` FOREIGN KEY (`workspace_id`,`property_id`) REFERENCES `workspace_property_definitions`(`workspace_id`,`property_id`),
  CONSTRAINT `fk_property_bindings_source_descriptor` FOREIGN KEY (`workspace_id`,`provider_id`,`source_instance_id`,`scope_kind`,`scope_external_id`,`external_property_id`) REFERENCES `source_property_descriptors`(`workspace_id`,`provider_id`,`source_instance_id`,`scope_kind`,`scope_external_id`,`external_property_id`),
  CONSTRAINT `chk_property_bindings_binding_ordinal` CHECK (binding_ordinal >= 0),
  CONSTRAINT `chk_property_bindings_direction` CHECK (direction in ('read','write','bidirectional')),
  CONSTRAINT `chk_property_bindings_approval_state` CHECK (approval_state in ('approved','pending','rejected')),
  CONSTRAINT `chk_property_bindings_workspace_id` CHECK (length(workspace_id) = 16),
  CONSTRAINT `chk_property_bindings_value_contract_revision` CHECK (value_contract_revision >= 0),
  CONSTRAINT `chk_property_bindings_mapping_version` CHECK (mapping_version >= 0),
  CONSTRAINT `chk_property_bindings_lifecycle_state` CHECK (lifecycle_state in ('active','tombstoned')),
  CONSTRAINT `chk_property_bindings_property_id` CHECK (length(property_id) = 16)
);

-- create "workspace_property_terms" table
CREATE TABLE `workspace_property_terms` (
  `workspace_id` blob NOT NULL,
  `property_id` blob NOT NULL,
  `term_kind` text NOT NULL,
  `ordinal` integer NOT NULL,
  `term_value` text NOT NULL,
  `seed_owner` text,
  `seed_version` integer,
  `seed_source_version` text,
  PRIMARY KEY (`workspace_id`,`property_id`,`term_kind`,`ordinal`),
  CONSTRAINT `fk_workspace_property_terms_workspace` FOREIGN KEY (`workspace_id`) REFERENCES `workspace_metadata`(`workspace_id`),
  CONSTRAINT `fk_workspace_property_terms_definition` FOREIGN KEY (`workspace_id`,`property_id`) REFERENCES `workspace_property_definitions`(`workspace_id`,`property_id`),
  CONSTRAINT `chk_workspace_property_terms_term_kind` CHECK (term_kind in ('search_alias','legacy_alias')),
  CONSTRAINT `chk_workspace_property_terms_ordinal` CHECK (ordinal >= 0),
  CONSTRAINT `chk_workspace_property_terms_property_id` CHECK (length(property_id) = 16),
  CONSTRAINT `chk_workspace_property_terms_workspace_id` CHECK (length(workspace_id) = 16)
);

-- create unique index "idx_term_value" to workspace_property_terms
CREATE UNIQUE INDEX `idx_term_value` ON `workspace_property_terms`(`workspace_id`,`property_id`,`term_kind`,`term_value`);
