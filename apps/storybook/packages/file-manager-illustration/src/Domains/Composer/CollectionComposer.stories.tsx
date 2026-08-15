import type { Meta, StoryObj } from "@storybook/react-vite"
import { useEffect, useRef, useState } from "react"
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
  readonly includeSubfolders: boolean
  readonly conditions: readonly ComposerCondition[]
}

const baseDraft = (): DraftState => ({
  query: "Find PDFs modified this month",
  scopes: ["/VoyagerFixtures/Documents"],
  includeSubfolders: true,
  conditions: [
    {
      id: "file_kind",
      property: "Kind",
      propertySymbol: "tag",
      operator: "Contains any",
      value: "PDF",
    },
    {
      id: "modification_date",
      property: "Content modification date",
      propertySymbol: "calendar.badge.clock",
      operator: "Is greater than",
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
  // 네이티브 초기화: initialProperty면 baseDraft 대상 조건의 operator를 복원한다
  const [operator, setOperator] = useState<ComposerOperatorOption | undefined>(() => {
    if (initialProperty == null) return undefined
    const initialCondition = baseDraft().conditions.find(
      (condition) =>
        condition.id === initialProperty.key || condition.property === initialProperty.label,
    )
    return initialCondition == null
      ? undefined
      : initialProperty.operators.find((option) => option.label === initialCondition.operator)
  })
  const [isProcessing, setIsProcessing] = useState(false)
  const [scopePickerOpen, setScopePickerOpen] = useState(false)
  const [toast, setToast] = useState<
    { readonly type: "info" | "error"; readonly message: string } | undefined
  >()
  const [duplicateMessage, setDuplicateMessage] = useState<string>()
  const [editingPropertyId, setEditingPropertyId] = useState<string>()
  // 네이티브 cancelSearch/cancelFilters: Stop은 진행 중 타이머를 취소한다
  const submitTimer = useRef<number | undefined>(undefined)

  // 네이티브 ComposerSearchLifecycleMetricLogging: 토스트 4초 후 자동 해제
  useEffect(() => {
    if (toast == null) return
    const timer = window.setTimeout(() => setToast(undefined), 4000)
    return () => window.clearTimeout(timer)
  }, [toast])

  const commit = (next: DraftState) => {
    setHistory((current) => [...current, draft])
    setFuture([])
    setDraft(next)
  }

  const undo = () => {
    setFuture((current) => [draft, ...current])
    // 네이티브 ComposerHistoryReducer와 동일한 LIFO: 마지막 스냅샷을 복원한다
    setHistory((current) => {
      const last = current.at(-1)
      if (last != null) setDraft(last)
      return current.slice(0, -1)
    })
  }

  const redo = () => {
    setHistory((current) => [...current, draft])
    setFuture((current) => {
      const [next, ...rest] = current
      if (next != null) setDraft(next)
      return rest
    })
  }

  const clear = () => {
    commit({ query: "", scopes: [], includeSubfolders: true, conditions: [] })
    setStep("complete")
    setScopePickerOpen(false)
  }

  const save = () => {
    setToast({ type: "info", message: "Collection saved." })
  }

  const submit = () => {
    if (isProcessing) {
      window.clearTimeout(submitTimer.current)
      setIsProcessing(false)
      setToast(undefined)
      return
    }
    if (draft.query.trim().length === 0) return
    setIsProcessing(true)
    setToast(undefined)
    submitTimer.current = window.setTimeout(() => {
      setIsProcessing(false)
      setToast({ type: "info", message: "Collection query completed." })
    }, 900)
  }

  const addCondition = () => {
    // 네이티브 ComposerHistoryReducer: 실제 변경 시에만 스냅샷을 기록한다 (피커 열기는 step만 변경)
    setDuplicateMessage(undefined)
    setEditingPropertyId(undefined)
    setStep("property")
  }

  const removeCondition = (id: string) => {
    commit({ ...draft, conditions: draft.conditions.filter((condition) => condition.id !== id) })
    if (editingPropertyId === id) setEditingPropertyId(undefined)
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
    const resolved = item.startsWith("/") ? item : `/VoyagerFixtures/${item}`
    // 네이티브 pushHistory 계약: 동일 scope 재선택 시 빈 Undo 스냅샷을 만들지 않는다
    if (draft.scopes.length !== 1 || draft.scopes[0] !== resolved) {
      commit({ ...draft, scopes: [resolved] })
    }
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

  // 네이티브 조건 편집: 일치하는 조건을 갱신하고 없으면 추가한다
  const upsertCondition = (next: ComposerCondition) => {
    const matches = draft.conditions.some(
      (condition) => condition.id === next.id || condition.property === next.property,
    )
    commit({
      ...draft,
      conditions: matches
        ? draft.conditions.map((condition) =>
            condition.id === next.id || condition.property === next.property ? next : condition,
          )
        : [...draft.conditions, next],
    })
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
        ? {
            kind: "property",
            items: composerPropertyOptions,
            existingKeys: draft.conditions
              .map((condition) => condition.id)
              .filter((id) => id !== editingPropertyId),
            editingKey: editingPropertyId,
            duplicateMessage,
          }
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
                  includeSubfolders: draft.includeSubfolders,
                  rootOnly: draft.scopes.length === 0,
                  // 네이티브 makeScopeSections: 행 상태를 현재 selection에서 파생한다
                  items: [
                    "/VoyagerFixtures/Documents",
                    "/VoyagerFixtures/Projects",
                    "/VoyagerFixtures/Projects/Legacy",
                    "/VoyagerFixtures/Inbox",
                  ].map((path) => {
                    // 네이티브 resolvedCandidateState: direct base는 included+clearDirectRule,
                    // 상속 하위는 subfolders on일 때만 included(상속)이며 exclude를 제공한다
                    const isDirect = draft.scopes.includes(path)
                    const inherited =
                      !isDirect && draft.scopes.some((scope) => path.startsWith(`${scope}/`))
                    const included = isDirect || (inherited && draft.includeSubfolders)
                    const actions = isDirect
                      ? (["clearDirectRule"] as const)
                      : included
                        ? (["exclude"] as const)
                        : (["include", "exclude"] as const)
                    return {
                      path,
                      depth: Math.max(
                        0,
                        path.split("/").filter(Boolean).length -
                          "/VoyagerFixtures".split("/").filter(Boolean).length -
                          1,
                      ),
                      status: included ? ("included" as const) : ("available" as const),
                      kind: isDirect ? ("base" as const) : ("candidate" as const),
                      ruleSource: isDirect ? ("direct" as const) : undefined,
                      actions,
                    }
                  }),
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
      onToggleSubfolders={() => commit({ ...draft, includeSubfolders: !draft.includeSubfolders })}
      onScopeFeedbackAction={(action) =>
        setToast({ type: "info", message: `${action} scope change.` })
      }
      onSubmit={submit}
      onAddCondition={addCondition}
      onRemoveCondition={removeCondition}
      onPropertyClick={(id) => {
        setEditingPropertyId(id)
        setStep("property")
      }}
      onDismissDuplicate={() => setDuplicateMessage(undefined)}
      onPropertySelect={(propertyKey) => {
        const selectedProperty = composerPropertyOption(propertyKey)
        if (selectedProperty == null) return
        // 네이티브 handleAddCondition: 중복 키면 경고를 띄우고 picker를 유지한다 (편집 대상은 예외)
        if (
          propertyKey !== editingPropertyId &&
          draft.conditions.some((condition) => condition.id === propertyKey)
        ) {
          setDuplicateMessage(`"${selectedProperty.label}" is already added.`)
          return
        }
        setProperty(selectedProperty)
        setOperator(undefined)
        setDuplicateMessage(undefined)
        // 네이티브 startEditing: 편집 컨텍스트에서는 기존 조건을 교체한다
        const replacing =
          editingPropertyId != null
            ? draft.conditions.find((condition) => condition.id === editingPropertyId)
            : undefined
        commit({
          ...draft,
          conditions: replacing
            ? draft.conditions.map((condition) =>
                condition.id === editingPropertyId
                  ? {
                      id: selectedProperty.key,
                      property: selectedProperty.label,
                      propertySymbol: selectedProperty.symbol,
                      operator: "",
                      value: "",
                    }
                  : condition,
              )
            : [
                ...draft.conditions,
                {
                  id: selectedProperty.key,
                  property: selectedProperty.label,
                  propertySymbol: selectedProperty.symbol,
                  operator: "",
                  value: "",
                },
              ],
        })
        setEditingPropertyId(undefined)
        setStep("operator")
      }}
      onOperatorClick={(id) => {
        setEditingPropertyId(id)
        const target = draft.conditions.find((condition) => condition.id === id)
        // baseDraft 칩은 레지스트리 키가 아닌 표시 id를 쓰므로 라벨/심볼로 폴백 매핑한다
        const selectedProperty =
          composerPropertyOption(id) ??
          composerPropertyOptions.find(
            (property) =>
              property.label === target?.property || property.symbol === target?.propertySymbol,
          )
        if (target != null && selectedProperty != null) {
          setProperty(selectedProperty)
          setOperator(selectedProperty.operators.find((option) => option.label === target.operator))
          setStep("operator")
        }
      }}
      onOperatorSelect={(operatorCode) => {
        const selectedOperator = property?.operators.find((option) => option.code === operatorCode)
        if (selectedOperator == null || property == null) return
        setOperator(selectedOperator)
        upsertCondition({
          id: property.key,
          property: property.label,
          propertySymbol: property.symbol,
          operator: selectedOperator.label,
          value: "",
        })
        setStep(selectedOperator.editor.kind === "none" ? "complete" : "value")
      }}
      onValueClick={(id) => {
        setEditingPropertyId(id)
        const target = draft.conditions.find((condition) => condition.id === id)
        const selectedProperty =
          composerPropertyOption(id) ??
          composerPropertyOptions.find(
            (property) =>
              property.label === target?.property || property.symbol === target?.propertySymbol,
          )
        if (target != null && selectedProperty != null) {
          setProperty(selectedProperty)
          setOperator(selectedProperty.operators.find((option) => option.label === target.operator))
          setStep("value")
        }
      }}
      onValueCommit={(value) => {
        const target = editingCondition ?? {
          id: property?.key ?? "condition",
          property: property?.label ?? "Property",
          propertySymbol: property?.symbol ?? "questionmark",
          operator: operator?.label ?? "Operator",
          value: "",
        }
        upsertCondition({ ...target, value })
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
