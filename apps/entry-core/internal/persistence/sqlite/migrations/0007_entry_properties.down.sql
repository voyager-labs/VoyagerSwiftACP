-- Reverse of 0007_entry_properties. Never executed at runtime; exists for
-- ADR-014 artifact-format compliance. 자식 테이블부터 역순으로 삭제한다.
DROP TABLE `entry_property_assignment_values`;
DROP TABLE `entry_property_assignments`;
DROP TABLE `workspace_property_options`;
