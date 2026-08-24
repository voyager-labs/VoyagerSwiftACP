import type { Meta, StoryObj } from "@storybook/react-vite"
import { ComposerConditionChip } from "../../../../packages/file-manager-illustration/src/Domains/Composer/ComposerConditionChip"
import { composerPropertyOption } from "../../../../packages/file-manager-illustration/src/Domains/Composer/composer-condition-options"

// 카탈로그 단일 소스: 칩 픽스처의 라벨·심볼을 정규 카탈로그에서 파생한다
const catalogEntry = (key: string) => {
  const option = composerPropertyOption(key)
  if (option == null) throw new Error(`Unknown property key: ${key}`)
  return option
}

// 네이티브 composerPropertyOptions 라벨·심볼과 동일한 결정적 픽스처만 사용한다
const textCondition = {
  id: "name_stem",
  property: catalogEntry("name_stem").label,
  propertySymbol: catalogEntry("name_stem").symbol,
  operator: "Contains",
  value: "Voyager",
} as const

const kindCondition = {
  id: "file_kind",
  property: catalogEntry("file_kind").label,
  propertySymbol: catalogEntry("file_kind").symbol,
  operator: "Contains any",
  value: '["PDF", "Image"]',
  editorKind: "list",
} as const

const dateCondition = {
  id: "modification_date",
  property: catalogEntry("modification_date").label,
  propertySymbol: catalogEntry("modification_date").symbol,
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
      property: catalogEntry("number_of_pages").label,
      propertySymbol: catalogEntry("number_of_pages").symbol,
      operator: "Is greater than",
      value: "24",
    },
  },
}

export const SizeUnitCondition: Story = {
  args: {
    condition: {
      id: "size_unit",
      property: catalogEntry("size").label,
      propertySymbol: catalogEntry("size").symbol,
      operator: "Is greater than",
      value: "10 MB",
    },
  },
}

export const SizeRangeCondition: Story = {
  args: {
    condition: {
      id: "size_range",
      property: catalogEntry("size").label,
      propertySymbol: catalogEntry("size").symbol,
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
      property: catalogEntry("modification_date").label,
      propertySymbol: catalogEntry("modification_date").symbol,
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
      property: catalogEntry("modification_date").label,
      propertySymbol: catalogEntry("modification_date").symbol,
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
      property: catalogEntry("is_invisible").label,
      propertySymbol: catalogEntry("is_invisible").symbol,
      operator: "Is",
      value: "True",
    },
  },
}

export const StringListCondition: Story = {
  args: {
    condition: {
      id: "keywords",
      property: catalogEntry("keywords").label,
      propertySymbol: catalogEntry("keywords").symbol,
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
      property: catalogEntry("modification_date").label,
      propertySymbol: catalogEntry("modification_date").symbol,
      operator: "Is today",
      value: "",
    },
  },
}

export const ArityZeroListCondition: Story = {
  args: {
    condition: {
      id: "keywords_exists",
      property: catalogEntry("keywords").label,
      propertySymbol: catalogEntry("keywords").symbol,
      operator: "Exists",
      value: "",
    },
  },
}

export const OperatorPlaceholderCondition: Story = {
  args: {
    condition: {
      id: "name_unspecified",
      property: catalogEntry("name_stem").label,
      propertySymbol: catalogEntry("name_stem").symbol,
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
      property: catalogEntry("name_stem").label,
      propertySymbol: catalogEntry("name_stem").symbol,
      operator: "Contains",
      value: "Voyager release notes draft for the upcoming quarterly review document",
    },
  },
}
