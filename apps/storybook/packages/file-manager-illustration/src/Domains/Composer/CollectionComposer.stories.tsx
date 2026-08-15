import type { Meta, StoryObj } from "@storybook/react-vite"
import { useState } from "react"
import { CollectionComposer } from "./CollectionComposer"
import {
  type ComposerOperatorOption,
  type ComposerPropertyOption,
  composerPropertyOption,
} from "./composer-condition-options"
import { composerPropertyOptions } from "./composer-condition-options"
import { type ComposerCondition, type ComposerFixture, composerFixtures } from "./composer-fixtures"

type SelectionStep = "property" | "operator" | "value" | "complete"

type DraftState = {
  readonly query: string
  readonly scopes: readonly string[]
  readonly conditions: readonly ComposerCondition[]
}

const baseDraft = (): DraftState => ({
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
})

const ComposerSelectionFlow = ({
  initialPropertyKey,
}: { readonly initialPropertyKey?: string }) => {
  const initialProperty =
    initialPropertyKey == null ? undefined : composerPropertyOption(initialPropertyKey)
  const [draft, setDraft] = useState<DraftState>(baseDraft)
  const [history, setHistory] = useState<readonly DraftState[]>([])
  const [future, setFuture] = useState<readonly DraftState[]>([])
  const [step, setStep] = useState<SelectionStep>(initialProperty == null ? "property" : "operator")
  const [property, setProperty] = useState<ComposerPropertyOption | undefined>(initialProperty)
  const [operator, setOperator] = useState<ComposerOperatorOption | undefined>()
  const [isProcessing, setIsProcessing] = useState(false)
  const [scopePickerOpen, setScopePickerOpen] = useState(false)
  const [includeSubfolders, setIncludeSubfolders] = useState(true)
  const [toast, setToast] = useState<
    { readonly type: "info" | "error"; readonly message: string } | undefined
  >()

  const commit = (next: DraftState) => {
    setHistory((current) => [...current, draft])
    setFuture([])
    setDraft(next)
  }

  const undo = () => {
    setFuture((current) => [draft, ...current])
    setHistory((current) => {
      const [latest, ...rest] = current
      if (latest != null) setDraft(latest)
      return rest
    })
  }

  const redo = () => {
    setHistory((current) => [...current, draft])
    setFuture((current) => {
      const [latest, ...rest] = current
      if (latest != null) setDraft(latest)
      return rest
    })
  }

  const clear = () => {
    commit({ query: "", scopes: [], conditions: [] })
    setStep("complete")
    setScopePickerOpen(false)
  }

  const save = () => {
    setToast({ type: "info", message: "Collection saved." })
  }

  const submit = () => {
    if (isProcessing || draft.query.trim().length === 0) return
    setIsProcessing(true)
    setToast(undefined)
    window.setTimeout(() => {
      setIsProcessing(false)
      setToast({ type: "info", message: "Collection query completed." })
    }, 900)
  }

  const addCondition = () => {
    commit({ ...draft })
    setStep("property")
  }

  const removeCondition = (id: string) => {
    commit({ ...draft, conditions: draft.conditions.filter((condition) => condition.id !== id) })
    if (property?.key === id) {
      setProperty(undefined)
      setOperator(undefined)
      setStep("complete")
    }
  }

  const removeScope = (path: string) => {
    commit({ ...draft, scopes: draft.scopes.filter((scope) => scope !== path) })
  }

  const selectScope = (item: string) => {
    commit({
      ...draft,
      scopes: [item.startsWith("/") ? item : `/VoyagerFixtures/${item}`],
    })
    setScopePickerOpen(false)
  }

  const scopeAction = (path: string, action: "include" | "exclude" | "clearDirectRule") => {
    if (action === "include") {
      commit({ ...draft, scopes: [...draft.scopes, path] })
      setToast({ type: "info", message: `Scope added: ${path.split("/").at(-1)}` })
      return
    }
    if (action === "exclude") {
      setToast({ type: "error", message: `Scope excluded: ${path.split("/").at(-1)}` })
      return
    }
    commit({
      ...draft,
      scopes: draft.scopes.filter((scope) => scope !== path && !scope.startsWith(`${path}/`)),
    })
  }

  const editingCondition =
    property == null
      ? undefined
      : draft.conditions.find(
          (condition) => condition.id === property.key || condition.property === property.label,
        )

  const fixture: ComposerFixture = {
    ...composerFixtures.emptyDraft,
    query: draft.query,
    scopes: draft.scopes,
    conditions: draft.conditions,
    canUndo: history.length > 0,
    canRedo: future.length > 0,
    canSave: draft.conditions.length > 0 || draft.query.trim().length > 0,
    isProcessing,
    transientFeedback: toast,
    picker:
      step === "property"
        ? { kind: "property", items: composerPropertyOptions }
        : step === "operator" && property != null
          ? {
              kind: "operator",
              conditionID: property.key,
              selectedCode: operator?.code ?? property.operators[0]?.code ?? "",
              options: property.operators,
            }
          : step === "value" && operator != null
            ? {
                kind: "value",
                conditionID: property?.key,
                editor: operator.editor,
                selectedValue: editingCondition?.value,
              }
            : scopePickerOpen
              ? {
                  kind: "scope",
                  query: "",
                  currentSummary: draft.scopes[0]?.split("/").at(-1) ?? "This Mac",
                  includeSubfolders,
                  rootOnly: draft.scopes.length === 0,
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
                      actions: ["include", "exclude"],
                    },
                    {
                      path: "/VoyagerFixtures/Projects/Legacy",
                      depth: 1,
                      status: "excluded",
                      kind: "exception",
                      ruleSource: "direct",
                      actions: ["clearDirectRule"],
                    },
                    {
                      path: "/VoyagerFixtures/Inbox",
                      depth: 0,
                      status: "available",
                      kind: "candidate",
                      actions: ["include"],
                    },
                  ],
                }
              : undefined,
  }

  return (
    <CollectionComposer
      fixture={fixture}
      onUndo={undo}
      onRedo={redo}
      onClear={clear}
      onSave={save}
      onEditScope={() => {
        setStep("complete")
        setScopePickerOpen((open) => !open)
      }}
      onScopeSelect={selectScope}
      onScopeRemove={removeScope}
      onScopeAction={scopeAction}
      onToggleSubfolders={() => setIncludeSubfolders((current) => !current)}
      onScopeFeedbackAction={(action) =>
        setToast({ type: "info", message: `${action} scope change.` })
      }
      onSubmit={submit}
      onAddCondition={addCondition}
      onRemoveCondition={removeCondition}
      onPropertyClick={() => setStep("property")}
      onPropertySelect={(propertyKey) => {
        const selectedProperty = composerPropertyOption(propertyKey)
        if (selectedProperty == null) return
        setProperty(selectedProperty)
        setOperator(undefined)
        // 네이티브 ComposerConditionEditingReducer는 신규 조건을 append 한다
        const id = `${selectedProperty.key}-${draft.conditions.length + 1}`
        commit({
          ...draft,
          conditions: [
            ...draft.conditions,
            {
              id,
              property: selectedProperty.label,
              propertySymbol: selectedProperty.symbol,
              operator: "",
              value: "",
            },
          ],
        })
        setStep("operator")
      }}
      onOperatorClick={() => setStep("operator")}
      onOperatorSelect={(operatorCode) => {
        const selectedOperator = property?.operators.find((option) => option.code === operatorCode)
        if (selectedOperator == null) return
        setOperator(selectedOperator)
        commit({
          ...draft,
          conditions: draft.conditions.map((condition) =>
            condition.id === property?.key || condition.property === property?.label
              ? {
                  ...condition,
                  operator: selectedOperator.label,
                  value: selectedOperator.editor.kind === "none" ? "" : "",
                }
              : condition,
          ),
        })
        setStep(selectedOperator.editor.kind === "none" ? "complete" : "value")
      }}
      onValueClick={() => {
        if (operator?.editor.kind !== "none") setStep("value")
      }}
      onValueCommit={(value) => {
        commit({
          ...draft,
          conditions: draft.conditions.map((condition) =>
            condition.id === property?.key || condition.property === property?.label
              ? { ...condition, value }
              : condition,
          ),
        })
        setStep("complete")
      }}
    />
  )
}

const meta = {
  component: CollectionComposer,
  tags: ["autodocs"],
  parameters: { layout: "fullscreen" },
  args: { fixture: composerFixtures.emptyDraft },
} satisfies Meta<typeof CollectionComposer>

export default meta
type Story = StoryObj<typeof meta>

export const EmptyDraft: Story = {}
export const PopulatedDraft: Story = { args: { fixture: composerFixtures.populatedDraft } }
export const DiscardMode: Story = { args: { fixture: composerFixtures.discardMode } }
export const SaveAsMode: Story = { args: { fixture: composerFixtures.saveAsMode } }
export const SavedConfirmation: Story = { args: { fixture: composerFixtures.savedConfirmation } }
export const CompactNarrow: Story = {
  args: { fixture: composerFixtures.populatedDraft },
  decorators: [
    (Story) => (
      <div className="collection-composer-compact-story-frame">
        <Story />
      </div>
    ),
  ],
}
export const PropertyPickerOpen: Story = { args: { fixture: composerFixtures.propertyPickerOpen } }
export const OperatorPickerOpen: Story = { args: { fixture: composerFixtures.operatorPickerOpen } }
export const ValuePickerOpen: Story = { args: { fixture: composerFixtures.valuePickerOpen } }
export const AllPropertyTypesFlow: Story = { render: () => <ComposerSelectionFlow /> }
export const TextFlow: Story = {
  render: () => <ComposerSelectionFlow initialPropertyKey="name_stem" />,
}
export const NumberFlow: Story = {
  render: () => <ComposerSelectionFlow initialPropertyKey="number_of_pages" />,
}
export const SizeUnitFlow: Story = {
  render: () => <ComposerSelectionFlow initialPropertyKey="size" />,
}
export const DateFlow: Story = {
  render: () => <ComposerSelectionFlow initialPropertyKey="modification_date" />,
}
export const BooleanFlow: Story = {
  render: () => <ComposerSelectionFlow initialPropertyKey="is_invisible" />,
}
export const StringListFlow: Story = {
  render: () => <ComposerSelectionFlow initialPropertyKey="keywords" />,
}
export const CategoricalFlow: Story = {
  render: () => <ComposerSelectionFlow initialPropertyKey="file_kind" />,
}
export const Processing: Story = { args: { fixture: composerFixtures.processing } }
export const ScopeApplied: Story = { args: { fixture: composerFixtures.scopeApplied } }
export const ScopeApplying: Story = { args: { fixture: composerFixtures.scopeApplying } }
export const ScopeFailed: Story = { args: { fixture: composerFixtures.scopeFailed } }
export const QueryRecovery: Story = { args: { fixture: composerFixtures.queryRecovery } }
