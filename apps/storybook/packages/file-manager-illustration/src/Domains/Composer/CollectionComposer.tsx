import { type FC, useEffect, useRef, useState } from "react"
import { SFSymbol } from "../../Foundations/SFSymbol"
import { ComposerConditionChip } from "./ComposerConditionChip"
import { ComposerOperatorPicker } from "./ComposerOperatorPicker"
import { ComposerPropertyPicker } from "./ComposerPropertyPicker"
import { ComposerScopeSummaryChip } from "./ComposerScopeSummaryChip"
import { ComposerScopeTokenChip } from "./ComposerScopeTokenChip"
import { ComposerValuePicker } from "./ComposerValuePicker"
import type {
  ComposerClearMode,
  ComposerFixture,
  ComposerSaveMode,
  ComposerScopeItem,
  ComposerScopePicker,
} from "./composer-fixtures"

export type CollectionComposerProps = {
  readonly fixture: ComposerFixture
  readonly onUndo?: () => void
  readonly onRedo?: () => void
  readonly onClear?: () => void
  readonly onSave?: () => void
  readonly onEditScope?: () => void
  readonly onScopeSelect?: (item: string) => void
  readonly onScopeRemove?: (path: string) => void
  readonly onScopeAction?: (path: string, action: "include" | "exclude" | "clearDirectRule") => void
  readonly onToggleSubfolders?: () => void
  readonly onScopeFeedbackAction?: (action: "Undo" | "Redo") => void
  readonly onSubmit?: () => void
  readonly onAddCondition?: () => void
  readonly onRemoveCondition?: (id: string) => void
  readonly onPropertyClick?: (id: string) => void
  readonly onDismissDuplicate?: () => void
  readonly onOperatorClick?: (id: string) => void
  readonly onPropertySelect?: (property: string) => void
  readonly onOperatorSelect?: (operator: string) => void
  readonly onValueClick?: (id: string) => void
  readonly onValueCommit?: (value: string) => void
}

// 네이티브 ComposerFeedbackToastView는 종류와 무관하게 경고 삼각형 하나만 렌더
const transientFeedbackIcon = "exclamationmark.triangle.fill"

const clearButtonContent = (
  mode: ComposerClearMode,
): { readonly symbol: string; readonly label: string } => ({
  symbol: "xmark.square",
  label: mode === "discard" ? "Discard" : "Clear",
})

const saveButtonContent = (
  mode: ComposerSaveMode,
): { readonly symbol: string; readonly label: string } =>
  mode === "saveAs"
    ? { symbol: "square.and.arrow.down", label: "Save As" }
    : { symbol: "tray.and.arrow.down", label: "Save" }

export const CollectionComposer: FC<CollectionComposerProps> = ({
  fixture,
  onUndo,
  onRedo,
  onClear,
  onSave,
  onEditScope,
  onScopeSelect,
  onScopeRemove,
  onScopeAction,
  onToggleSubfolders,
  onScopeFeedbackAction,
  onSubmit,
  onAddCondition,
  onRemoveCondition,
  onPropertyClick,
  onDismissDuplicate,
  onOperatorClick,
  onPropertySelect,
  onOperatorSelect,
  onValueClick,
  onValueCommit,
}) => {
  const clearContent = clearButtonContent(fixture.clearMode ?? "clear")
  const saveContent = saveButtonContent(fixture.saveMode ?? "save")

  return (
    <section className="collection-composer" aria-label="Collection Composer">
      <div className="collection-composer-input-row">
        <ComposerSymbolButton
          symbol="arrow.uturn.backward"
          label="Undo"
          disabled={!fixture.canUndo || fixture.isProcessing}
          onClick={onUndo}
        />
        <ComposerSymbolButton
          symbol="arrow.uturn.forward"
          label="Redo"
          disabled={!fixture.canRedo || fixture.isProcessing}
          onClick={onRedo}
        />
        <label className="collection-composer-query">
          <input
            aria-label="Collection query"
            value={fixture.query}
            readOnly
            placeholder="Describe the collection you want..."
            title={fixture.query}
          />
          <ComposerSymbolButton
            symbol={fixture.isProcessing ? "stop.fill" : "arrow.right"}
            label={fixture.isProcessing ? "Stop" : "Submit"}
            accent
            disabled={!fixture.isProcessing && fixture.query.trim().length === 0}
            onClick={onSubmit}
          />
        </label>
        <ComposerTextButton
          symbol={clearContent.symbol}
          label={clearContent.label}
          disabled={
            fixture.isProcessing ||
            (fixture.query.trim().length === 0 &&
              fixture.scopes.length === 0 &&
              fixture.conditions.length === 0)
          }
          onClick={onClear}
        />
        <ComposerTextButton
          symbol={saveContent.symbol}
          label={saveContent.label}
          disabled={!fixture.canSave || fixture.isProcessing}
          onClick={onSave}
        />
      </div>

      <div className="collection-composer-separator" />

      <div className={`collection-composer-chip-area${fixture.isProcessing ? " locked" : ""}`}>
        <div className="collection-composer-scope-row" aria-label="Collection scope">
          <div className="collection-composer-scope-tokens">
            {fixture.scopes.length === 0 ? (
              <ComposerScopeTokenChip title="This Mac" />
            ) : (
              fixture.scopes.map((scope) => (
                <ComposerScopeTokenChip
                  title={scope.split("/").at(-1) ?? scope}
                  path={scope}
                  removable
                  onRemove={() => onScopeRemove?.(scope)}
                  key={scope}
                />
              ))
            )}
          </div>
          <ComposerSymbolButton
            symbol="chevron.down"
            label="Edit scopes"
            compact
            disabled={fixture.isProcessing}
            onClick={onEditScope}
          />
        </div>

        <div className="collection-composer-condition-row" aria-label="Collection conditions">
          {fixture.conditions.map((condition) => (
            <ComposerConditionChip
              condition={condition}
              key={condition.id}
              operatorExpanded={
                fixture.picker?.kind === "operator" && fixture.picker.conditionID === condition.id
              }
              valueExpanded={
                fixture.picker?.kind === "value" && fixture.picker.conditionID === condition.id
              }
              onPropertyClick={() => onPropertyClick?.(condition.id)}
              onOperatorClick={() => onOperatorClick?.(condition.id)}
              onValueClick={() => onValueClick?.(condition.id)}
              onRemove={() => onRemoveCondition?.(condition.id)}
            />
          ))}
          <ComposerSymbolButton
            symbol="plus"
            label="Add condition"
            compact
            disabled={fixture.isProcessing}
            onClick={onAddCondition}
          />
        </div>
      </div>

      {!fixture.isProcessing && fixture.picker?.kind === "property" && (
        <ComposerPropertyPicker
          picker={fixture.picker}
          onSelect={onPropertySelect}
          onDismissDuplicate={onDismissDuplicate}
        />
      )}
      {!fixture.isProcessing && fixture.picker?.kind === "operator" && (
        <ComposerOperatorPicker picker={fixture.picker} onSelect={onOperatorSelect} />
      )}
      {!fixture.isProcessing && fixture.picker?.kind === "value" && (
        <ComposerValuePicker
          key={fixture.picker.conditionID}
          picker={fixture.picker}
          onCommit={onValueCommit}
        />
      )}
      {!fixture.isProcessing && fixture.picker?.kind === "scope" && (
        <ScopePicker
          picker={fixture.picker}
          onSelect={onScopeSelect}
          onAction={onScopeAction}
          onToggleSubfolders={onToggleSubfolders}
          onFeedbackAction={onScopeFeedbackAction}
        />
      )}

      {fixture.transientFeedback != null && (
        <output className={`collection-composer-toast ${fixture.transientFeedback.type}`}>
          <SFSymbol name={transientFeedbackIcon} size={12} weight={600} />
          {fixture.transientFeedback.message}
        </output>
      )}
    </section>
  )
}

CollectionComposer.displayName = "CollectionComposer"

const ComposerSymbolButton: FC<{
  readonly symbol: string
  readonly label: string
  readonly disabled?: boolean
  readonly accent?: boolean
  readonly compact?: boolean
  readonly onClick?: () => void
}> = ({ symbol, label, disabled, accent, compact, onClick }) => (
  <button
    type="button"
    className={`collection-composer-symbol-button${accent ? " accent" : ""}${compact ? " compact" : ""}`}
    aria-label={label}
    disabled={disabled}
    onClick={onClick}
  >
    <SFSymbol name={symbol} size={compact ? 10 : accent ? 9 : 13} weight={accent ? 400 : 500} />
  </button>
)

const ComposerTextButton: FC<{
  readonly symbol: string
  readonly label: string
  readonly disabled?: boolean
  readonly onClick?: () => void
}> = ({ symbol, label, disabled, onClick }) => (
  <button
    type="button"
    className="collection-composer-text-button"
    disabled={disabled}
    onClick={onClick}
  >
    <SFSymbol name={symbol} size={11} weight={500} />
    {label}
  </button>
)

type ScopeAction = "include" | "exclude" | "clearDirectRule"

// 네이티브 ScopeTreeRowView의 액션 심볼/라벨 매핑
const scopeActionSymbol = (action: ScopeAction, kind: ComposerScopeItem["kind"]): string => {
  if (action === "include") return "checkmark"
  if (action === "exclude") return "minus"
  return kind === "exception" ? "arrow.uturn.backward" : "xmark"
}

const scopeActionLabel = (item: ComposerScopeItem, action: ScopeAction): string => {
  if (action === "include") return "Include scope"
  if (action === "exclude") return "Exclude scope"
  if (item.kind === "exception") return "Restore scope"
  return "Remove direct rule"
}

const ScopePicker: FC<{
  readonly picker: ComposerScopePicker
  readonly onSelect?: (item: string) => void
  readonly onAction?: (path: string, action: "include" | "exclude" | "clearDirectRule") => void
  readonly onToggleSubfolders?: () => void
  readonly onFeedbackAction?: (action: "Undo" | "Redo") => void
}> = ({ picker, onSelect, onAction, onToggleSubfolders, onFeedbackAction }) => {
  const [queryValue, setQueryValue] = useState(picker.query)
  const searchFieldRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    setQueryValue(picker.query)
    searchFieldRef.current?.focus()
  }, [picker.query])

  const query = queryValue.trim()
  const matches = (item: ComposerScopeItem) =>
    query.length === 0 ||
    item.path.toLowerCase().includes(query.toLowerCase()) ||
    (item.displayName ?? "").toLowerCase().includes(query.toLowerCase())
  const filtered = picker.items.filter(matches)

  // 네이티브 makeScopeSections: Current scope(root/base/exception) + candidate 섹션,
  // 검색 중에는 candidate 섹션이 먼저 오고 결과가 없으면 No Results 푸터를 렌더
  const currentRows = filtered.filter((item) => item.kind !== "candidate")
  const candidateRows = filtered.filter((item) => item.kind === "candidate")
  const noResults = query.length > 0 && filtered.length === 0
  const candidateSection = {
    title: noResults
      ? `No Results for "${query}"`
      : query.length > 0
        ? `Search Results for "${query}"`
        : "Suggested locations",
    rows: candidateRows,
    noResults,
  }
  const currentSection = { title: "Current scope", rows: currentRows, noResults: false }
  // 네이티브 isCandidateSectionPrimary: 검색 중에만 candidate 섹션이 먼저 온다
  const sections =
    query.length > 0 ? [candidateSection, currentSection] : [currentSection, candidateSection]
  const visibleSections = sections.filter((section) => section.rows.length > 0 || section.noResults)

  const scopeRow = (item: ComposerScopeItem) => {
    const name = item.displayName ?? item.path.split("/").at(-1) ?? item.path
    // 네이티브 handleTreeRowBodyTap: base=편집기 오픈, candidate=단일 액션 즉시 실행, exception/root=무시
    const bodyTap = () => {
      // 네이티브 handleTreeRowBodyTap: base/exclusion 본문은 편집(교체 금지), candidate만 단일 액션
      if (item.kind === "base" || item.kind === "exception" || item.kind === "root") return
      if (item.kind === "candidate" && item.actions.length === 1)
        onAction?.(item.path, item.actions[0])
    }
    const primaryAction = item.actions[0]
    return (
      <div
        className={`collection-composer-scope-tree-row ${item.status} kind-${item.kind}`}
        key={item.path}
        title={item.ruleSource === "inherited" ? `Inherited from ${item.inheritedFrom}` : undefined}
      >
        <button
          type="button"
          className="collection-composer-scope-tree-body"
          style={{ paddingInlineStart: `${10 + item.depth * 16}px` }}
          onClick={bodyTap}
        >
          <SFSymbol name="folder" size={12} />
          <span className="collection-composer-scope-row-copy">
            <strong>{name}</strong>
            <small title={item.path}>{item.path}</small>
          </span>
          <span className={`collection-composer-scope-row-badge ${item.status}`}>
            {item.status === "included"
              ? "Included"
              : item.status === "excluded"
                ? "Excluded"
                : "Available"}
          </span>
        </button>
        {primaryAction != null && (
          <button
            type="button"
            className="collection-composer-scope-action"
            aria-label={scopeActionLabel(item, primaryAction)}
            onClick={() => onAction?.(item.path, primaryAction)}
          >
            <SFSymbol name={scopeActionSymbol(primaryAction, item.kind)} size={9} weight={600} />
            <span>{scopeActionLabel(item, primaryAction)}</span>
          </button>
        )}
      </div>
    )
  }

  return (
    <dialog className="collection-composer-scope-picker" open aria-label="Scope picker">
      <div className="collection-composer-picker-search">
        <SFSymbol name="magnifyingglass" size={12} />
        <input
          ref={searchFieldRef}
          type="search"
          aria-label="Search directories"
          placeholder="Search directories..."
          value={queryValue}
          onChange={(event) => setQueryValue(event.currentTarget.value)}
        />
        {queryValue.length > 0 && (
          <button
            type="button"
            className="collection-composer-picker-search-clear"
            aria-label="Clear directory search"
            onClick={() => setQueryValue("")}
          >
            <SFSymbol name="xmark.circle.fill" size={12} />
          </button>
        )}
      </div>
      <div className="collection-composer-scope-summary-chip-area">
        <ComposerScopeSummaryChip primary={picker.currentSummary} />
        {!picker.rootOnly && (
          <button
            type="button"
            className="collection-composer-scope-subfolders"
            aria-pressed={picker.includeSubfolders}
            onClick={onToggleSubfolders}
          >
            <span>{picker.includeSubfolders ? "Subfolders On" : "Subfolders Off"}</span>
            <SFSymbol
              name={picker.includeSubfolders ? "checkmark.circle.fill" : "circle"}
              size={11}
              weight={600}
            />
          </button>
        )}
      </div>
      {picker.feedback != null && (
        <div
          className={`collection-composer-scope-feedback ${picker.feedback.phase.toLowerCase()}`}
        >
          <SFSymbol
            name={
              picker.feedback.phase === "Failed"
                ? "exclamationmark.triangle.fill"
                : picker.feedback.phase === "Applying"
                  ? "clock.arrow.circlepath"
                  : "checkmark.circle.fill"
            }
            size={12}
            weight={600}
          />
          <strong>{picker.feedback.title}</strong>
          <span>{picker.feedback.phase}</span>
          {picker.feedback.showsUndo && (
            <button
              type="button"
              aria-label="Undo latest scope change"
              onClick={() => onFeedbackAction?.("Undo")}
            >
              Undo
            </button>
          )}
          {picker.feedback.showsRedo && (
            <button
              type="button"
              aria-label="Redo latest scope change"
              onClick={() => onFeedbackAction?.("Redo")}
            >
              Redo
            </button>
          )}
        </div>
      )}
      <div className="collection-composer-scope-list">
        {visibleSections.map((section, index) => (
          <div className="collection-composer-scope-section" key={section.title}>
            {index > 0 && <div className="collection-composer-scope-section-divider" />}
            <small className="collection-composer-scope-section-header">{section.title}</small>
            {section.rows.map(scopeRow)}
            {section.noResults && (
              <div className="collection-composer-scope-no-results">
                <strong>No Results</strong>
                <span>No directories found for &quot;{query}&quot;.</span>
                <small>
                  Try another search or clear the search to return to the previous list.
                </small>
              </div>
            )}
          </div>
        ))}
      </div>
    </dialog>
  )
}
