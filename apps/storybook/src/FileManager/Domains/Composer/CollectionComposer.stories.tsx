import type { Meta, StoryObj } from "@storybook/react-vite"
import { useEffect, useRef, useState } from "react"
import { CollectionComposer } from "../../../../packages/file-manager-illustration/src/Domains/Composer/CollectionComposer"
import {
  type ComposerOperatorOption,
  type ComposerPropertyOption,
  composerPropertyOption,
} from "../../../../packages/file-manager-illustration/src/Domains/Composer/composer-condition-options"
import { composerPropertyOptions } from "../../../../packages/file-manager-illustration/src/Domains/Composer/composer-condition-options"
import { encodeRelativeLiteral } from "../../../../packages/file-manager-illustration/src/Domains/Composer/composer-date-literal"
import {
  type ComposerCondition,
  type ComposerFixture,
  composerFixtures,
} from "../../../../packages/file-manager-illustration/src/Domains/Composer/composer-fixtures"

type SelectionStep = "property" | "operator" | "value" | "complete"

type DraftState = {
  readonly query: string
  readonly scopes: readonly string[]
  readonly excludedScopes: readonly string[]
  readonly includeSubfolders: boolean
  readonly conditions: readonly ComposerCondition[]
}

const scopeSummary = (scopes: readonly string[], excludedScopes: readonly string[]): string => {
  if (scopes.length === 0) return "This Mac"
  const names = scopes.map((scope) => scope.split("/").at(-1) ?? scope)
  const summary = names.join(", ")
  return excludedScopes.length > 0 ? `${summary} · ${excludedScopes.length} excluded` : summary
}

const baseDraft = (): DraftState => ({
  query: composerFixtures.populatedDraft.query,
  scopes: composerFixtures.populatedDraft.scopes,
  excludedScopes: [],
  includeSubfolders: true,
  conditions: composerFixtures.populatedDraft.conditions,
})

const ComposerSelectionFlow = ({
  initialPropertyKey,
}: { readonly initialPropertyKey?: string }) => {
  const initialProperty =
    initialPropertyKey == null ? undefined : composerPropertyOption(initialPropertyKey)
  // 네이티브 handleAddCondition: operator picker를 열기 전에 편집 대상 placeholder 조건을
  // seed해, baseDraft에 없는 property flow도 어떤 조건을 편집하는지 표면에서 확인하게 한다
  const [draft, setDraft] = useState<DraftState>(() => {
    if (initialProperty == null) return baseDraft()
    const existing = baseDraft().conditions.some(
      (condition) =>
        condition.id === initialProperty.key || condition.property === initialProperty.label,
    )
    if (existing) return baseDraft()
    return {
      ...baseDraft(),
      conditions: [
        ...baseDraft().conditions,
        {
          id: initialProperty.key,
          property: initialProperty.label,
          propertySymbol: initialProperty.symbol,
          operator: "",
          value: "",
        },
      ],
    }
  })
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

  const closePicker = () => {
    setStep("complete")
    setEditingPropertyId(undefined)
    setScopePickerOpen(false)
  }

  const undo = () => {
    setFuture((current) => [draft, ...current])
    // 네이티브 ComposerHistoryReducer와 동일한 LIFO: 마지막 스냅샷을 복원한다
    // 네이티브 setText처럼 쿼리는 히스토리 밖 상태다: 복원 시 현재 쿼리를 유지한다
    setHistory((current) => {
      const last = current.at(-1)
      if (last != null) {
        setDraft({ ...last, query: draft.query })
        closePicker()
      }
      return current.slice(0, -1)
    })
  }

  const redo = () => {
    setHistory((current) => [...current, draft])
    setFuture((current) => {
      const [next, ...rest] = current
      if (next != null) {
        setDraft({ ...next, query: draft.query })
        closePicker()
      }
      return rest
    })
  }

  const clear = () => {
    commit({ query: "", scopes: [], excludedScopes: [], includeSubfolders: true, conditions: [] })
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
    closePicker()
    submitTimer.current = window.setTimeout(() => {
      setIsProcessing(false)
      setToast({ type: "info", message: "Collection query completed." })
    }, 900)
  }

  const addCondition = () => {
    // 네이티브 ComposerHistoryReducer: 실제 변경 시에만 스냅샷을 기록한다 (피커 열기는 step만 변경)
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
    // 네이티브 handleRemoveScope: 대상 base만 정확히 제거하고 그 하위 예외만 정리한다
    // (subfolders off에서 독립적으로 선택된 하위 direct base는 보존)
    commit({
      ...draft,
      scopes: draft.scopes.filter((scope) => scope !== path),
      excludedScopes: draft.excludedScopes.filter(
        (excluded) => excluded !== path && !excluded.startsWith(`${path}/`),
      ),
    })
  }

  const selectScope = (item: string) => {
    const resolved = item.startsWith("/") ? item : `/Fixture/${item}`
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
      commit({ ...draft, excludedScopes: [...draft.excludedScopes, path] })
      setToast({ type: "error", message: `Scope excluded: ${path.split("/").at(-1)}` })
      return
    }
    commit({
      ...draft,
      scopes: draft.scopes.filter((scope) => scope !== path),
      // 네이티브 fromCanonicalScopes: base 제거 시 그 하위 예외만 정리한다
      // (독립적으로 선택된 하위 direct base는 보존)
      excludedScopes: draft.excludedScopes.filter(
        (excluded) => excluded !== path && !excluded.startsWith(`${path}/`),
      ),
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
            // 네이티브 selectedKey: 편집 중 조건의 현재 property에 체크마크를 표시한다
            selectedKey: editingPropertyId,
          }
        : step === "operator" && property != null
          ? {
              kind: "operator",
              conditionID: property.key,
              selectedCode: operator?.code ?? "",
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
                  currentSummary: scopeSummary(draft.scopes, draft.excludedScopes),
                  includeSubfolders: draft.includeSubfolders,
                  rootOnly: draft.scopes.length === 0,
                  // 네이티브 makeScopeSections: 행 상태를 현재 selection에서 파생한다
                  items: [
                    "/Fixture/Documents",
                    "/Fixture/Projects",
                    "/Fixture/Projects/Legacy",
                    "/Fixture/Inbox",
                  ].map((path) => {
                    // 네이티브 resolvedCandidateState: direct base는 included+clearDirectRule,
                    // 상속 하위는 subfolders on일 때만 included(상속)이며 exclude를 제공한다
                    const isDirect = draft.scopes.includes(path)
                    const inherited =
                      !isDirect && draft.scopes.some((scope) => path.startsWith(`${scope}/`))
                    const included = isDirect || (inherited && draft.includeSubfolders)
                    const isExcluded = draft.excludedScopes.includes(path)
                    const actions = isExcluded
                      ? (["clearDirectRule"] as const)
                      : isDirect
                        ? (["clearDirectRule"] as const)
                        : included
                          ? (["exclude"] as const)
                          : // 네이티브 resolvedCandidateState: available 후보는 단일 include 액션만
                            (["include"] as const)
                    return {
                      path,
                      depth: Math.max(
                        0,
                        path.split("/").filter(Boolean).length -
                          "/Fixture".split("/").filter(Boolean).length -
                          1,
                      ),
                      status: isExcluded
                        ? ("excluded" as const)
                        : included
                          ? ("included" as const)
                          : ("available" as const),
                      kind: isExcluded
                        ? ("exception" as const)
                        : isDirect
                          ? ("base" as const)
                          : ("candidate" as const),
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
      onQueryChange={(query) => setDraft((current) => ({ ...current, query }))}
      onEditScope={() => {
        setStep("complete")
        setScopePickerOpen((open) => !open)
      }}
      onScopeSelect={selectScope}
      onScopeRemove={removeScope}
      onScopeAction={scopeAction}
      onToggleSubfolders={() => {
        const next = !draft.includeSubfolders
        commit({
          ...draft,
          includeSubfolders: next,
          // 네이티브 canonicalizeScopeRule: subfolders off면 상속 하위 예외를 정리한다
          excludedScopes: next
            ? draft.excludedScopes
            : draft.excludedScopes.filter(
                (path) => !draft.scopes.some((scope) => path.startsWith(`${scope}/`)),
              ),
        })
      }}
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
      onPropertySelect={(propertyKey) => {
        const selectedProperty = composerPropertyOption(propertyKey)
        if (selectedProperty == null) return
        // 네이티브 startEditing: 편집 컨텍스트에서는 기존 조건을 교체한다
        setProperty(selectedProperty)
        setOperator(undefined)
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
          editorKind: selectedOperator.editor.kind,
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
          editorKind: operator?.editor.kind,
          value: "",
        }
        // 편집 대상 조건에 editorKind가 없어도 operator에서 파생해 wire format 노출을 막는다
        upsertCondition({ ...target, value, editorKind: operator?.editor.kind })
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
  decorators: [
    (Story) => (
      <div className="collection-composer-story-frame">
        <Story />
      </div>
    ),
  ],
} satisfies Meta<typeof CollectionComposer>

export default meta
type Story = StoryObj<typeof meta>

export const EmptyDraft: Story = {}
export const PopulatedDraft: Story = { args: { fixture: composerFixtures.populatedDraft } }
export const OverflowMenu: Story = { args: { fixture: composerFixtures.overflowMenu } }
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
