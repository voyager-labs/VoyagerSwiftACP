ALTER TABLE `workspace_property_terms`
  ADD COLUMN `lifecycle_state` text NOT NULL DEFAULT 'active'
  CHECK (lifecycle_state in ('active','tombstoned'));
