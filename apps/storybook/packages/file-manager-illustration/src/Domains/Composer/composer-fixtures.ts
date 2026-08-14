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
  readonly operator: string
  readonly value: string
}

export type ComposerScopeFeedback = {
  readonly phase: "Applied" | "Applying" | "Failed"
  readonly title: string
  readonly action?: "Undo" | "Redo" | "Retry"
}

export type ComposerPropertyPicker = {
  readonly kind: "property"
  readonly items: readonly ComposerPropertyOption[]
}

export type ComposerOperatorPicker = {
  readonly kind: "operator"
  readonly conditionID: string
  readonly selectedCode: string
  readonly options: readonly ComposerOperatorOption[]
}

export type ComposerValuePicker = {
  readonly kind: "value"
  readonly editor: ComposerValueEditor
  readonly selectedValue?: string
  readonly error?: string
}

export type ComposerScopePicker = {
  readonly kind: "scope"
  readonly query: string
  readonly currentSummary: string
  readonly includeSubfolders: boolean
  readonly sectionTitle: string
  readonly items: readonly string[]
  readonly feedback?: ComposerScopeFeedback
}

// 네이티브 ComposerTopRowView와 동일하게 한 버튼이 모드에 따라 Clear/Discard, Save/Save As 로 전환
export type ComposerClearMode = "clear" | "discard"
export type ComposerSaveMode = "save" | "saveAs"

export type ComposerTransientFeedback = {
  readonly type: "success" | "warning" | "error"
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
      value: "This month",
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
    },
  },
  operatorPickerOpen: {
    ...populatedDraft,
    picker: {
      kind: "operator",
      conditionID: "kind",
      selectedCode: "eq",
      options:
        composerPropertyOptions.find((property) => property.key === "file_kind")?.operators ?? [],
    },
  },
  valuePickerOpen: {
    ...populatedDraft,
    picker: { kind: "value", editor: { kind: "boolean" }, selectedValue: "True" },
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
      sectionTitle: "Current scope",
      items: ["Documents"],
      feedback: { phase: "Applied", title: "Scope updated to Documents", action: "Undo" },
    },
  },
  scopeApplying: {
    ...populatedDraft,
    picker: {
      kind: "scope",
      query: "",
      currentSummary: "Documents",
      includeSubfolders: true,
      sectionTitle: "Current scope",
      items: ["Documents", "Projects"],
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
      sectionTitle: "Current scope",
      items: ["Documents", "Projects"],
      feedback: {
        phase: "Failed",
        title: "Scope change could not be fully applied",
        action: "Retry",
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
      type: "success" as const,
      message: "Collection saved.",
    },
  },
} satisfies Record<string, ComposerFixture>
