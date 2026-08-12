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

const ComposerSelectionFlow = ({
  initialPropertyKey,
}: { readonly initialPropertyKey?: string }) => {
  const initialProperty =
    initialPropertyKey == null ? undefined : composerPropertyOption(initialPropertyKey)
  const [step, setStep] = useState<SelectionStep>(initialProperty == null ? "property" : "operator")
  const [property, setProperty] = useState<ComposerPropertyOption | undefined>(initialProperty)
  const [operator, setOperator] = useState<ComposerOperatorOption | undefined>()
  const [condition, setCondition] = useState<ComposerCondition | null>(
    initialProperty == null
      ? null
      : {
          id: initialProperty.key,
          property: initialProperty.label,
          propertySymbol: initialProperty.symbol,
          operator: "Operator",
          value: "Value",
        },
  )

  const fixture: ComposerFixture = {
    ...composerFixtures.emptyDraft,
    conditions: condition == null ? [] : [condition],
    picker:
      step === "property"
        ? { kind: "property", items: composerPropertyOptions }
        : step === "operator" && property != null
          ? { kind: "operator", options: property.operators }
          : step === "value" && operator != null
            ? { kind: "value", editor: operator.editor }
            : undefined,
  }

  return (
    <CollectionComposer
      fixture={fixture}
      onAddCondition={() => setStep("property")}
      onPropertySelect={(propertyKey) => {
        const selectedProperty = composerPropertyOption(propertyKey)
        if (selectedProperty == null) return
        setProperty(selectedProperty)
        setOperator(undefined)
        setCondition({
          id: selectedProperty.key,
          property: selectedProperty.label,
          propertySymbol: selectedProperty.symbol,
          operator: "Operator",
          value: "Value",
        })
        setStep("operator")
      }}
      onOperatorClick={() => setStep("operator")}
      onOperatorSelect={(operatorCode) => {
        const selectedOperator = property?.operators.find((option) => option.code === operatorCode)
        if (selectedOperator == null) return
        setOperator(selectedOperator)
        setCondition((current) =>
          current == null
            ? current
            : {
                ...current,
                operator: selectedOperator.label,
                value: selectedOperator.editor.kind === "none" ? "" : "Value",
              },
        )
        setStep(selectedOperator.editor.kind === "none" ? "complete" : "value")
      }}
      onValueClick={() => {
        if (operator?.editor.kind !== "none") setStep("value")
      }}
      onValueCommit={(value) => {
        setCondition((current) => (current == null ? current : { ...current, value }))
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
export const ScopeFailed: Story = { args: { fixture: composerFixtures.scopeFailed } }
export const QueryRecovery: Story = { args: { fixture: composerFixtures.queryRecovery } }
