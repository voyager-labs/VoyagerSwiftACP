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
  readonly action?: "Undo" | "Redo"
}

export type ComposerPropertyPicker = {
  readonly kind: "property"
  readonly items: readonly ComposerPropertyOption[]
}

export type ComposerOperatorPicker = {
  readonly kind: "operator"
  readonly options: readonly ComposerOperatorOption[]
}

export type ComposerValuePicker = {
  readonly kind: "value"
  readonly editor: ComposerValueEditor
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

export type ComposerFixture = {
  readonly query: string
  readonly scopes: readonly string[]
  readonly conditions: readonly ComposerCondition[]
  readonly canUndo: boolean
  readonly canRedo: boolean
  readonly canSave: boolean
  readonly isProcessing?: boolean
  readonly transientFeedback?: string
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
  propertyPickerOpen: {
    ...populatedDraft,
    picker: {
      kind: "property",
      items: composerPropertyOptions,
    },
  },
  operatorPickerOpen: {
    ...populatedDraft,
    picker: { kind: "operator", options: composerPropertyOptions[0].operators },
  },
  valuePickerOpen: {
    ...populatedDraft,
    picker: { kind: "value", editor: { kind: "boolean" } },
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
      items: ["Documents", "Projects"],
      feedback: { phase: "Applied", title: "Scope updated to Documents", action: "Undo" },
    },
  },
  scopeFailed: {
    ...populatedDraft,
    picker: {
      kind: "scope",
      query: "",
      currentSummary: "Documents",
      includeSubfolders: true,
      sectionTitle: "Current scope",
      items: ["Documents", "Projects"],
      feedback: { phase: "Failed", title: "Scope change could not be fully applied" },
    },
  },
  queryRecovery: {
    ...populatedDraft,
    transientFeedback: "Couldn’t run the collection query. Review the draft and try again.",
  },
} satisfies Record<string, ComposerFixture>
