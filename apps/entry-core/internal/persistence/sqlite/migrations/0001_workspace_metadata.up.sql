-- create "workspace_metadata" table
CREATE TABLE `workspace_metadata` (
  `singleton` integer NOT NULL DEFAULT 1,
  `workspace_id` blob NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`singleton`),
  CONSTRAINT `chk_workspace_metadata_singleton` CHECK (singleton = 1),
  CONSTRAINT `chk_workspace_metadata_workspace_id` CHECK (length(workspace_id) = 16)
);
