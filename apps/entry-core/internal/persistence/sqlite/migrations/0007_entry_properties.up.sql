-- Workspace-scoped select options for Property definitions. Option value는
-- label이 아니라 option_id로 참조되며 비활성 선택지도 기존 assignment
-- read-back 보존을 위해 행이 유지된다. CHECK/UNIQUE는 GORM desired schema와
-- 동일하고, 워크스페이스 소유와 정의 참조 foreign key는 Atlas GORM 로더가
-- 표현할 수 없어 여기에 hand-written으로 존재한다(0002 관례와 같다).
CREATE TABLE `workspace_property_options` (
  `workspace_id` blob NOT NULL,
  `option_id` blob NOT NULL,
  `property_id` blob NOT NULL,
  `label` text NOT NULL,
  `color` text NOT NULL,
  `ordinal` integer NOT NULL,
  `active` boolean NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`workspace_id`,`option_id`),
  CONSTRAINT `fk_workspace_property_options_workspace` FOREIGN KEY (`workspace_id`) REFERENCES `workspace_metadata`(`workspace_id`),
  CONSTRAINT `fk_workspace_property_options_definition` FOREIGN KEY (`workspace_id`, `property_id`) REFERENCES `workspace_property_definitions`(`workspace_id`, `property_id`),
  CONSTRAINT `chk_workspace_property_options_workspace_id` CHECK (length(workspace_id) = 16),
  CONSTRAINT `chk_workspace_property_options_option_id` CHECK (length(option_id) = 16),
  CONSTRAINT `chk_workspace_property_options_property_id` CHECK (length(property_id) = 16),
  CONSTRAINT `chk_workspace_property_options_label` CHECK (length(label) >= 1),
  CONSTRAINT `chk_workspace_property_options_color` CHECK (length(color) <= 64),
  CONSTRAINT `chk_workspace_property_options_ordinal` CHECK (ordinal >= 0)
);

-- 정의별 선택지 ordinal의 유일성(중복 순서 실패 닫기).
CREATE UNIQUE INDEX `idx_option_property_ordinal` ON `workspace_property_options`(`workspace_id`,`property_id`,`ordinal`);

-- (workspace_id, entry_id, property_id) 자연 키의 local authoritative
-- assignment header다. surrogate ID는 없고 revision은 항상 1 이상이다
-- (revision 0은 저장되지 않은 implicit unset뿐이다). 값 payload는 자식 값
-- 테이블에 저장된다.
CREATE TABLE `entry_property_assignments` (
  `workspace_id` blob NOT NULL,
  `entry_id` text NOT NULL,
  `property_id` blob NOT NULL,
  `target_kind` text NOT NULL,
  `state` text NOT NULL,
  `record_revision` integer NOT NULL,
  `value_contract_revision` integer NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`workspace_id`,`entry_id`,`property_id`),
  CONSTRAINT `fk_entry_property_assignments_workspace` FOREIGN KEY (`workspace_id`) REFERENCES `workspace_metadata`(`workspace_id`),
  CONSTRAINT `fk_entry_property_assignments_definition` FOREIGN KEY (`workspace_id`, `property_id`) REFERENCES `workspace_property_definitions`(`workspace_id`, `property_id`),
  CONSTRAINT `chk_entry_property_assignments_workspace_id` CHECK (length(workspace_id) = 16),
  CONSTRAINT `chk_entry_property_assignments_entry_id` CHECK (length(entry_id) = 47 AND entry_id LIKE 'ent:%'),
  CONSTRAINT `chk_entry_property_assignments_property_id` CHECK (length(property_id) = 16),
  CONSTRAINT `chk_entry_property_assignments_target_kind` CHECK (target_kind in ('core_native','locator_derived')),
  CONSTRAINT `chk_entry_property_assignments_state` CHECK (state in ('unset','null','value')),
  CONSTRAINT `chk_entry_property_assignments_record_revision` CHECK (record_revision >= 1),
  CONSTRAINT `chk_entry_property_assignments_value_contract_revision` CHECK (value_contract_revision >= 1)
);

-- ordered assignment 값 멤버다. value_kind 판별 컬럼과 정확히 하나의 typed
-- payload 컬럼 조합만 허용되며(serialized JSON blob 금지), header 행 삭제 시
-- cascade로 함께 삭제된다.
CREATE TABLE `entry_property_assignment_values` (
  `workspace_id` blob NOT NULL,
  `entry_id` text NOT NULL,
  `property_id` blob NOT NULL,
  `ordinal` integer NOT NULL,
  `value_kind` text NOT NULL,
  `boolean_value` boolean,
  `decimal_value` text,
  `date_value` text,
  `timestamp_value` text,
  `text_value` text,
  `option_id` blob,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`workspace_id`,`entry_id`,`property_id`,`ordinal`),
  CONSTRAINT `fk_entry_property_assignment_values_assignment` FOREIGN KEY (`workspace_id`, `entry_id`, `property_id`) REFERENCES `entry_property_assignments`(`workspace_id`, `entry_id`, `property_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_entry_property_assignment_values_option` FOREIGN KEY (`workspace_id`, `option_id`) REFERENCES `workspace_property_options`(`workspace_id`, `option_id`),
  CONSTRAINT `chk_entry_property_assignment_values_workspace_id` CHECK (length(workspace_id) = 16),
  CONSTRAINT `chk_entry_property_assignment_values_entry_id` CHECK (length(entry_id) = 47 AND entry_id LIKE 'ent:%'),
  CONSTRAINT `chk_entry_property_assignment_values_property_id` CHECK (length(property_id) = 16),
  CONSTRAINT `chk_entry_property_assignment_values_ordinal` CHECK (ordinal >= 0),
  CONSTRAINT `chk_entry_property_assignment_values_value_kind` CHECK ((value_kind = 'boolean' AND boolean_value IS NOT NULL AND decimal_value IS NULL AND date_value IS NULL AND timestamp_value IS NULL AND text_value IS NULL AND option_id IS NULL) OR (value_kind = 'decimal' AND boolean_value IS NULL AND decimal_value IS NOT NULL AND date_value IS NULL AND timestamp_value IS NULL AND text_value IS NULL AND option_id IS NULL) OR (value_kind = 'date' AND boolean_value IS NULL AND decimal_value IS NULL AND date_value IS NOT NULL AND timestamp_value IS NULL AND text_value IS NULL AND option_id IS NULL) OR (value_kind = 'timestamp' AND boolean_value IS NULL AND decimal_value IS NULL AND date_value IS NULL AND timestamp_value IS NOT NULL AND text_value IS NULL AND option_id IS NULL) OR (value_kind = 'text' AND boolean_value IS NULL AND decimal_value IS NULL AND date_value IS NULL AND timestamp_value IS NULL AND text_value IS NOT NULL AND option_id IS NULL) OR (value_kind = 'option_ref' AND boolean_value IS NULL AND decimal_value IS NULL AND date_value IS NULL AND timestamp_value IS NULL AND text_value IS NULL AND option_id IS NOT NULL)),
  CONSTRAINT `chk_entry_property_assignment_values_option_id` CHECK (option_id IS NULL OR length(option_id) = 16)
);
