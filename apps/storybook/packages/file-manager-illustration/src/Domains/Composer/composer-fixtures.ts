import { composerPropertyOptions } from "./composer-condition-options"
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
  readonly duplicateMessage?: string
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

// 네이티브 ComposerTopRowView와 동일하게 한 버튼이 모드에 따라 Clear/Discard, Save/Save As 로 전환
export type ComposerClearMode = "clear" | "discard"
export type ComposerSaveMode = "save" | "saveAs"

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
  readonly clearMode?: ComposerClearMode
  readonly saveMode?: ComposerSaveMode
  readonly isProcessing?: boolean
  readonly transientFeedback?: ComposerTransientFeedback
  readonly picker?:
    | ComposerPropertyPicker
    | ComposerOperatorPicker
    | ComposerScopePicker
    | ComposerValuePicker
}

const populatedDraft = {
  query: "Find PDFs modified this month",
  scopes: ["/VoyagerFixtures/Documents"],
  conditions: [
    {
      id: "kind",
      property: "Kind",
      propertySymbol: "tag",
      operator: "Equals",
      value: "pdf",
    },
    {
      id: "modified",
      property: "Modified",
      propertySymbol: "calendar.badge.clock",
      operator: "is after",
      value: "voyager.relativeDate:v1:past:30:day:2026-01-01",
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
  discardMode: {
    ...populatedDraft,
    clearMode: "discard" as const,
  },
  saveAsMode: {
    ...populatedDraft,
    saveMode: "saveAs" as const,
  },
  propertyPickerOpen: {
    ...populatedDraft,
    picker: {
      kind: "property",
      items: composerPropertyOptions,
      existingKeys: ["file_kind", "modification_date"],
    },
  },
  operatorPickerOpen: {
    ...populatedDraft,
    picker: {
      kind: "operator",
      conditionID: "kind",
      selectedCode: "any",
      options:
        composerPropertyOptions.find((property) => property.key === "file_kind")?.operators ?? [],
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
          path: "/VoyagerFixtures/Documents",
          depth: 0,
          status: "included",
          kind: "base",
          ruleSource: "direct",
          actions: ["clearDirectRule"],
        },
        {
          path: "/VoyagerFixtures/Projects",
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
          path: "/VoyagerFixtures/Documents",
          depth: 0,
          status: "included",
          kind: "base",
          ruleSource: "direct",
          actions: ["clearDirectRule"],
        },
        {
          path: "/VoyagerFixtures/Projects",
          depth: 0,
          status: "included",
          kind: "base",
          ruleSource: "direct",
          actions: ["clearDirectRule"],
        },
        {
          path: "/VoyagerFixtures/Projects/Legacy",
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
          path: "/VoyagerFixtures/Documents",
          depth: 0,
          status: "included",
          kind: "base",
          ruleSource: "direct",
          actions: ["clearDirectRule"],
        },
        {
          path: "/VoyagerFixtures/Projects",
          depth: 0,
          status: "included",
          kind: "base",
          ruleSource: "inherited",
          inheritedFrom: "/VoyagerFixtures",
          actions: [],
        },
        {
          path: "/VoyagerFixtures/Inbox",
          depth: 0,
          status: "available",
          kind: "candidate",
          actions: ["include", "exclude"],
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
