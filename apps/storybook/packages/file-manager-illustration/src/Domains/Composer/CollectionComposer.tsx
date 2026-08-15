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
  readonly onToggleSubfolders?: () => void
  readonly onScopeFeedbackAction?: (action: "Undo" | "Redo") => void
  readonly onSubmit?: () => void
  readonly onAddCondition?: () => void
  readonly onRemoveCondition?: (id: string) => void
  readonly onPropertyClick?: () => void
  readonly onOperatorClick?: () => void
  readonly onPropertySelect?: (property: string) => void
  readonly onOperatorSelect?: (operator: string) => void
  readonly onValueClick?: () => void
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
  onToggleSubfolders,
  onScopeFeedbackAction,
  onSubmit,
  onAddCondition,
  onRemoveCondition,
  onPropertyClick,
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
          disabled={!fixture.canUndo}
          onClick={onUndo}
        />
        <ComposerSymbolButton
          symbol="arrow.uturn.forward"
          label="Redo"
          disabled={!fixture.canRedo}
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
          onClick={onClear}
        />
        <ComposerTextButton
          symbol={saveContent.symbol}
          label={saveContent.label}
          disabled={!fixture.canSave}
          onClick={onSave}
        />
      </div>

      <div className="collection-composer-separator" />

      <div className="collection-composer-chip-area">
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
              onPropertyClick={onPropertyClick}
              onOperatorClick={onOperatorClick}
              onValueClick={onValueClick}
              onRemove={() => onRemoveCondition?.(condition.id)}
            />
          ))}
          <ComposerSymbolButton
            symbol="plus"
            label="Add condition"
            compact
            onClick={onAddCondition}
          />
        </div>
      </div>

      {fixture.picker?.kind === "property" && (
        <ComposerPropertyPicker picker={fixture.picker} onSelect={onPropertySelect} />
      )}
      {fixture.picker?.kind === "operator" && (
        <ComposerOperatorPicker picker={fixture.picker} onSelect={onOperatorSelect} />
      )}
      {fixture.picker?.kind === "value" && (
        <ComposerValuePicker picker={fixture.picker} onCommit={onValueCommit} />
      )}
      {fixture.picker?.kind === "scope" && (
        <ScopePicker
          picker={fixture.picker}
          onSelect={onScopeSelect}
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

const ScopePicker: FC<{
  readonly picker: ComposerScopePicker
  readonly onSelect?: (item: string) => void
  readonly onToggleSubfolders?: () => void
  readonly onFeedbackAction?: (action: "Undo" | "Redo") => void
}> = ({ picker, onSelect, onToggleSubfolders, onFeedbackAction }) => {
  const [queryValue, setQueryValue] = useState(picker.query)
  const searchFieldRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    setQueryValue(picker.query)
    searchFieldRef.current?.focus()
  }, [picker.query])

  const query = queryValue.trim()
  const showsSearchResults = query.length > 0
  const searchResults = picker.items.filter((item) =>
    item.path.toLowerCase().includes(query.toLowerCase()),
  )

  const scopeRow = (item: ComposerScopeItem) => {
    const name = item.path.split("/").at(-1) ?? item.path
    return (
      <button
        type="button"
        key={item.path}
        style={{ paddingInlineStart: `${8 + item.depth * 16}px` }}
        onClick={() => onSelect?.(item.path)}
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
            <button type="button" onClick={() => onFeedbackAction?.("Undo")}>
              Undo
            </button>
          )}
          {picker.feedback.showsRedo && (
            <button type="button" onClick={() => onFeedbackAction?.("Redo")}>
              Redo
            </button>
          )}
        </div>
      )}
      <div className="collection-composer-scope-list">
        <small>{showsSearchResults ? `Search results for "${query}"` : picker.sectionTitle}</small>
        {showsSearchResults && searchResults.length === 0 ? (
          <div className="collection-composer-scope-empty">No matching directories</div>
        ) : (
          (showsSearchResults ? searchResults : picker.items).map(scopeRow)
        )}
      </div>
    </dialog>
  )
}
