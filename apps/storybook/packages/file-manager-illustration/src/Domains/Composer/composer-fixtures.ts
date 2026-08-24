import { composerPropertyOption, composerPropertyOptions } from "./composer-condition-options"
import type {
  ComposerOperatorOption,
  ComposerPropertyOption,
  ComposerValueEditor,
} from "./composer-condition-options"

export type ComposerCondition = {
  readonly id: string
  readonly property: string
  readonly propertySymbol: string
  // 네이티브 ConditionChipPropertyOperatorView와 동일하게 operator가 비어 있으면 "Operator" 폴백 표기
  readonly operator: string
  readonly value: string
  // 값 직렬화에 쓰인 editor kind: 목록 JSON 디코딩을 list 조건에만 적용한다
  readonly editorKind?: ComposerValueEditor["kind"]
}

export type ComposerScopeFeedback = {
  readonly phase: "Applied" | "Applying" | "Failed"
  readonly title: string
  readonly showsUndo?: boolean
  readonly showsRedo?: boolean
}

// 네이티브 ComposerScopeTreeRow의 depth/kind/visualState/ruleSource/availableActions 계약 반영
export type ComposerScopeItem = {
  readonly path: string
  readonly depth: number
  readonly displayName?: string
  readonly status: "included" | "excluded" | "available"
  readonly kind: "root" | "base" | "exception" | "candidate"
  readonly ruleSource?: "direct" | "inherited"
  readonly inheritedFrom?: string
  readonly actions: readonly ("include" | "exclude" | "clearDirectRule")[]
}

export type ComposerPropertyPicker = {
  readonly kind: "property"
  readonly items: readonly ComposerPropertyOption[]
  readonly existingKeys?: readonly string[]
  readonly editingKey?: string
  // 편집 중인 조건의 현재 property: 네이티브 selectedKey 체크마크 계약
  readonly selectedKey?: string
}

export type ComposerOperatorPicker = {
  readonly kind: "operator"
  readonly conditionID: string
  readonly selectedCode: string
  readonly options: readonly ComposerOperatorOption[]
}

export type ComposerValuePicker = {
  readonly kind: "value"
  readonly conditionID?: string
  readonly editor: ComposerValueEditor
  readonly selectedValue?: string
  readonly error?: string
}

export type ComposerScopePicker = {
  readonly kind: "scope"
  readonly query: string
  readonly currentSummary: string
  readonly includeSubfolders: boolean
  readonly rootOnly?: boolean
  readonly items: readonly ComposerScopeItem[]
  readonly feedback?: ComposerScopeFeedback
}

export type ComposerTransientFeedback = {
  // 네이티브 ComposerTransientFeedback는 info/error만 지원
  readonly type: "info" | "error"
  readonly message: string
}

export type ComposerFixture = {
  readonly query: string
  readonly scopes: readonly string[]
  readonly conditions: readonly ComposerCondition[]
  readonly canUndo: boolean
  readonly canRedo: boolean
  readonly canSave: boolean
  readonly canDiscard?: boolean
  readonly overflowOpen?: boolean
  readonly isProcessing?: boolean
  readonly transientFeedback?: ComposerTransientFeedback
  readonly picker?:
    | ComposerPropertyPicker
    | ComposerOperatorPicker
    | ComposerScopePicker
    | ComposerValuePicker
}

const fixtureOption = (key: string) => {
  const option = composerPropertyOption(key)
  if (option == null) throw new Error(`Unknown property key: ${key}`)
  return option
}

const populatedDraft = {
  query: "Find files named Voyager",
  scopes: ["/Fixture/Documents"],
  conditions: [
    {
      id: "name_stem",
      // 카탈로그 단일 소스: 라벨·심볼을 드리프트 없이 파생한다
      property: fixtureOption("name_stem").label,
      propertySymbol: fixtureOption("name_stem").symbol,
      operator: "Is",
      value: "Voyager",
    },
  ],
  canUndo: true,
  canRedo: false,
  canSave: true,
} satisfies ComposerFixture

export const composerFixtures = {
  emptyDraft: {
    query: "",
    scopes: [],
    conditions: [],
    canUndo: false,
    canRedo: false,
    canSave: false,
  },
  populatedDraft,
  overflowMenu: {
    ...populatedDraft,
    canDiscard: true,
    overflowOpen: true,
  },
  propertyPickerOpen: {
    ...populatedDraft,
    picker: {
      kind: "property",
      items: composerPropertyOptions,
      existingKeys: ["name_stem"],
    },
  },
  operatorPickerOpen: {
    ...populatedDraft,
    picker: {
      kind: "operator",
      conditionID: "name_stem",
      selectedCode: "eq",
      options:
        composerPropertyOptions.find((property) => property.key === "name_stem")?.operators ?? [],
    },
  },
  valuePickerOpen: {
    ...populatedDraft,
    conditions: [
      ...populatedDraft.conditions,
      {
        id: "is_invisible",
        property: "Is hidden",
        propertySymbol: "eye.slash",
        operator: "Is",
        value: "True",
      },
    ],
    picker: {
      kind: "value",
      conditionID: "is_invisible",
      editor: { kind: "boolean" },
      selectedValue: "True",
    },
  },
  processing: {
    ...populatedDraft,
    isProcessing: true,
  },
  scopeApplied: {
    ...populatedDraft,
    picker: {
      kind: "scope",
      query: "",
      currentSummary: "Documents",
      includeSubfolders: true,
      items: [
        {
          path: "/Fixture/Documents",
          depth: 0,
          status: "included",
          kind: "base",
          ruleSource: "direct",
          actions: ["clearDirectRule"],
        },
        {
          path: "/Fixture/Projects",
          depth: 0,
          status: "available",
          kind: "candidate",
          actions: ["include"],
        },
      ],
      feedback: { phase: "Applied", title: "Scope updated to Documents", showsUndo: true },
    },
  },
  scopeApplying: {
    ...populatedDraft,
    picker: {
      kind: "scope",
      query: "",
      currentSummary: "Documents, Projects",
      includeSubfolders: true,
      items: [
        {
          path: "/Fixture/Documents",
          depth: 0,
          status: "included",
          kind: "base",
          ruleSource: "direct",
          actions: ["clearDirectRule"],
        },
        {
          path: "/Fixture/Projects",
          depth: 0,
          status: "included",
          kind: "base",
          ruleSource: "direct",
          actions: ["clearDirectRule"],
        },
        {
          path: "/Fixture/Projects/Legacy",
          depth: 1,
          status: "excluded",
          kind: "exception",
          ruleSource: "direct",
          actions: ["clearDirectRule"],
        },
      ],
      feedback: { phase: "Applying", title: "Updating scope" },
    },
  },
  scopeFailed: {
    ...populatedDraft,
    picker: {
      kind: "scope",
      query: "",
      currentSummary: "Documents, Projects",
      includeSubfolders: true,
      items: [
        {
          path: "/Fixture/Documents",
          depth: 0,
          status: "included",
          kind: "base",
          ruleSource: "direct",
          actions: ["clearDirectRule"],
        },
        {
          path: "/Fixture/Projects",
          depth: 0,
          status: "included",
          kind: "base",
          ruleSource: "inherited",
          inheritedFrom: "/Fixture",
          actions: [],
        },
        {
          path: "/Fixture/Inbox",
          depth: 0,
          status: "available",
          kind: "candidate",
          // 네이티브 resolvedCandidateState: available 후보는 단일 include 액션만 갖는다
          actions: ["include"],
        },
      ],
      feedback: {
        phase: "Failed",
        title: "Scope change could not be fully applied",
        showsUndo: true,
        showsRedo: true,
      },
    },
  },
  queryRecovery: {
    ...populatedDraft,
    transientFeedback: {
      type: "error" as const,
      message: "Couldn’t run the collection query. Review the draft and try again.",
    },
  },
  savedConfirmation: {
    ...populatedDraft,
    transientFeedback: {
      type: "info" as const,
      message: "Collection saved.",
    },
  },
} satisfies Record<string, ComposerFixture>
