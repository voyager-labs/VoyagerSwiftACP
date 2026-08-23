import type { Meta, StoryObj } from "@storybook/react-vite"
import { ComposerConditionChip } from "../../../../packages/file-manager-illustration/src/Domains/Composer/ComposerConditionChip"

// 네이티브 composerPropertyOptions 라벨·심볼과 동일한 결정적 픽스처만 사용한다
const textCondition = {
  id: "name_stem",
  property: "Name",
  propertySymbol: "doc.text",
  operator: "Contains",
  value: "Voyager",
} as const

const kindCondition = {
  id: "file_kind",
  property: "Kind",
  propertySymbol: "tag",
  operator: "Contains any",
  value: '["PDF", "Image"]',
  editorKind: "list",
} as const

const dateCondition = {
  id: "modification_date",
  property: "Content modification date",
  propertySymbol: "calendar.badge.clock",
  // 정규 date gt 계약(registry singleDate): 카탈로그 dateOperators의 라벨과 YYYY-MM-DD 값 사용
  operator: "Is greater than",
  value: "2024-06-01",
  editorKind: "date",
} as const

const meta = {
  component: ComposerConditionChip,
  tags: ["autodocs"],
  decorators: [
    (Story) => (
      <div className="collection-composer-specimen">
        <Story />
      </div>
    ),
  ],
  args: { condition: textCondition },
} satisfies Meta<typeof ComposerConditionChip>

export default meta
type Story = StoryObj<typeof meta>

// === 칩 상태 ===

export const Active: Story = {}
export const Inactive: Story = { args: { inactive: true } }
export const RemoveVisible: Story = { args: { showRemove: true } }
export const OperatorExpanded: Story = { args: { operatorExpanded: true } }
export const ValueExpanded: Story = { args: { valueExpanded: true } }

// === 값 편집기 변이 ===

export const NumberCondition: Story = {
  args: {
    condition: {
      id: "number_of_pages",
      property: "Number of pages",
      propertySymbol: "doc.richtext",
      operator: "Is greater than",
      value: "24",
    },
  },
}

export const SizeUnitCondition: Story = {
  args: {
    condition: {
      id: "size_unit",
      property: "File size",
      propertySymbol: "arrow.up.left.and.arrow.down.right",
      operator: "Is greater than",
      value: "10 MB",
    },
  },
}

export const SizeRangeCondition: Story = {
  args: {
    condition: {
      id: "size_range",
      property: "File size",
      propertySymbol: "arrow.up.left.and.arrow.down.right",
      operator: "Is between",
      value: "1 MB – 500 MB",
    },
  },
}

export const DateCondition: Story = {
  args: { condition: dateCondition },
}

export const RelativeDateCondition: Story = {
  args: {
    condition: {
      // 고정 앵커 날짜로 시계 비의존성을 유지하고 리터럴 디코딩 경로를 검증한다
      id: "date_relative",
      property: "Content modification date",
      propertySymbol: "calendar.badge.clock",
      operator: "Is greater than",
      value: "voyager.relativeDate:v1:past:7:day:2024-06-01",
      editorKind: "date",
    },
  },
}

export const DateRangeCondition: Story = {
  args: {
    condition: {
      id: "date_range",
      property: "Content modification date",
      propertySymbol: "calendar.badge.clock",
      operator: "Is between",
      value: "2024-01-01 – 2024-03-31",
      editorKind: "dateRange",
    },
  },
}

export const BooleanCondition: Story = {
  args: {
    condition: {
      id: "is_invisible",
      property: "Is hidden",
      propertySymbol: "eye.slash",
      operator: "Is",
      value: "True",
    },
  },
}

export const StringListCondition: Story = {
  args: {
    condition: {
      id: "keywords",
      property: "Keywords",
      propertySymbol: "text.badge.checkmark",
      operator: "Contains any",
      value: '["pdf", "docx"]',
      editorKind: "list",
    },
  },
}

export const CategoricalCondition: Story = {
  args: { condition: kindCondition },
}

// === 구조 엣지 ===

export const ArityZeroOperatorCondition: Story = {
  args: {
    condition: {
      id: "date_today",
      property: "Content modification date",
      propertySymbol: "calendar.badge.clock",
      operator: "Is today",
      value: "",
    },
  },
}

export const ArityZeroListCondition: Story = {
  args: {
    condition: {
      id: "keywords_exists",
      property: "Keywords",
      propertySymbol: "text.badge.checkmark",
      operator: "Exists",
      value: "",
    },
  },
}

export const OperatorPlaceholderCondition: Story = {
  args: {
    condition: {
      id: "name_unspecified",
      property: "Name",
      propertySymbol: "doc.text",
      operator: "",
      value: "",
    },
  },
}

// === 오버플로 ===

export const TruncatedValue: Story = {
  args: {
    condition: {
      id: "name_long",
      property: "Name",
      propertySymbol: "doc.text",
      operator: "Contains",
      value: "Voyager release notes draft for the upcoming quarterly review document",
    },
  },
}
