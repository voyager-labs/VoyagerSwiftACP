DROP INDEX `idx_term_value`;
CREATE UNIQUE INDEX `idx_term_value`
ON `workspace_property_terms` (`workspace_id`, `property_id`, `term_value`)
WHERE `lifecycle_state` = 'active';
