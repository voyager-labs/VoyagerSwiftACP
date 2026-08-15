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
  const [toast, setToast] = useState<
    { readonly type: "success" | "warning" | "error"; readonly message: string } | undefined
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
    setToast({ type: "success", message: "Collection saved." })
  }

  const submit = () => {
    if (isProcessing || draft.query.trim().length === 0) return
    setIsProcessing(true)
    setToast(undefined)
    window.setTimeout(() => {
      setIsProcessing(false)
      setToast({ type: "success", message: "Collection query completed." })
    }, 900)
  }

  const addCondition = () => {
    commit({ ...draft })
    setStep("property")
  }

  const selectScope = (item: string) => {
    commit({ ...draft, scopes: [`/VoyagerFixtures/${item}`] })
    setScopePickerOpen(false)
  }

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
            ? { kind: "value", editor: operator.editor, selectedValue: draft.conditions[0]?.value }
            : scopePickerOpen
              ? {
                  kind: "scope",
                  query: "",
                  currentSummary: draft.scopes[0]?.split("/").at(-1) ?? "This Mac",
                  includeSubfolders: true,
                  sectionTitle: "Current scope",
                  items: ["Documents", "Projects", "Inbox"],
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
      onSubmit={submit}
      onAddCondition={addCondition}
      onPropertySelect={(propertyKey) => {
        const selectedProperty = composerPropertyOption(propertyKey)
        if (selectedProperty == null) return
        setProperty(selectedProperty)
        setOperator(undefined)
        commit({
          ...draft,
          conditions: [
            {
              id: selectedProperty.key,
              property: selectedProperty.label,
              propertySymbol: selectedProperty.symbol,
              operator: "Operator",
              value: "Value",
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
          conditions: [
            {
              id: property?.key ?? "condition",
              property: property?.label ?? "Property",
              propertySymbol: property?.symbol ?? "questionmark",
              operator: selectedOperator.label,
              value: selectedOperator.editor.kind === "none" ? "" : "Value",
            },
          ],
        })
        setStep(selectedOperator.editor.kind === "none" ? "complete" : "value")
      }}
      onValueClick={() => {
        if (operator?.editor.kind !== "none") setStep("value")
      }}
      onValueCommit={(value) => {
        commit({
          ...draft,
          conditions: [
            {
              id: property?.key ?? "condition",
              property: property?.label ?? "Property",
              propertySymbol: property?.symbol ?? "questionmark",
              operator: operator?.label ?? "Operator",
              value,
            },
          ],
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
