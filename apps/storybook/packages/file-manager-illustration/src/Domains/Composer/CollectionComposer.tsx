import type { FC } from "react"
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
  ComposerScopePicker,
  ComposerTransientFeedback,
} from "./composer-fixtures"

export type CollectionComposerProps = {
  readonly fixture: ComposerFixture
  readonly onUndo?: () => void
  readonly onRedo?: () => void
  readonly onClear?: () => void
  readonly onSave?: () => void
  readonly onEditScope?: () => void
  readonly onScopeSelect?: (item: string) => void
  readonly onSubmit?: () => void
  readonly onAddCondition?: () => void
  readonly onOperatorClick?: () => void
  readonly onPropertySelect?: (property: string) => void
  readonly onOperatorSelect?: (operator: string) => void
  readonly onValueClick?: () => void
  readonly onValueCommit?: (value: string) => void
}

const transientFeedbackIcon = (type: ComposerTransientFeedback["type"]): string =>
  type === "success"
    ? "checkmark.circle.fill"
    : type === "warning"
      ? "exclamationmark.triangle.fill"
      : "xmark.octagon.fill"

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
  onSubmit,
  onAddCondition,
  onOperatorClick,
  onPropertySelect,
  onOperatorSelect,
  onValueClick,
  onValueCommit,
}) => {
  const clearContent = clearButtonContent(fixture.clearMode ?? "clear")
  const saveContent = saveButtonContent(fixture.saveMode ?? "save")

  return (
    <div className="collection-composer-overlay">
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
                valueExpanded={fixture.picker?.kind === "value"}
                onOperatorClick={onOperatorClick}
                onValueClick={onValueClick}
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
          <ScopePicker picker={fixture.picker} onSelect={onScopeSelect} />
        )}

        {fixture.transientFeedback != null && (
          <output className={`collection-composer-toast ${fixture.transientFeedback.type}`}>
            <SFSymbol
              name={transientFeedbackIcon(fixture.transientFeedback.type)}
              size={12}
              weight={600}
            />
            {fixture.transientFeedback.message}
          </output>
        )}
      </section>
    </div>
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
}> = ({ picker, onSelect }) => (
  <dialog className="collection-composer-scope-picker" open aria-label="Scope picker">
    <div className="collection-composer-picker-search">
      <SFSymbol name="magnifyingglass" size={12} />
      <span>{picker.query.length > 0 ? picker.query : "Search directories..."}</span>
    </div>
    <div className="collection-composer-scope-summary-chip-area">
      <ComposerScopeSummaryChip
        primary={picker.currentSummary}
        secondary={picker.includeSubfolders ? "Includes subfolders" : undefined}
      />
    </div>
    {picker.feedback != null && (
      <div className={`collection-composer-scope-feedback ${picker.feedback.phase.toLowerCase()}`}>
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
        {picker.feedback.action != null && <button type="button">{picker.feedback.action}</button>}
      </div>
    )}
    <div className="collection-composer-scope-list">
      <small>{picker.sectionTitle}</small>
      {picker.items.map((item) => (
        <button type="button" key={item} onClick={() => onSelect?.(item)}>
          <SFSymbol name="folder" size={12} />
          {item}
        </button>
      ))}
    </div>
  </dialog>
)
