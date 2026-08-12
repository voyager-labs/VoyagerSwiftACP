import type { FC } from "react"
import { SFSymbol } from "../../Foundations/SFSymbol"
import { ComposerConditionChip } from "./ComposerConditionChip"
import { ComposerOperatorPicker } from "./ComposerOperatorPicker"
import { ComposerPropertyPicker } from "./ComposerPropertyPicker"
import { ComposerScopeTokenChip } from "./ComposerScopeTokenChip"
import { ComposerValuePicker } from "./ComposerValuePicker"
import type { ComposerFixture, ComposerScopePicker } from "./composer-fixtures"

export type CollectionComposerProps = {
  readonly fixture: ComposerFixture
  readonly onAddCondition?: () => void
  readonly onOperatorClick?: () => void
  readonly onPropertySelect?: (property: string) => void
  readonly onOperatorSelect?: (operator: string) => void
  readonly onValueClick?: () => void
  readonly onValueCommit?: (value: string) => void
}

export const CollectionComposer: FC<CollectionComposerProps> = ({
  fixture,
  onAddCondition,
  onOperatorClick,
  onPropertySelect,
  onOperatorSelect,
  onValueClick,
  onValueCommit,
}) => (
  <div className="collection-composer-overlay">
    <section className="collection-composer" aria-label="Collection Composer">
      <div className="collection-composer-input-row">
        <ComposerSymbolButton
          symbol="arrow.uturn.backward"
          label="Undo"
          disabled={!fixture.canUndo}
        />
        <ComposerSymbolButton
          symbol="arrow.uturn.forward"
          label="Redo"
          disabled={!fixture.canRedo}
        />
        <label className="collection-composer-query">
          <span className="sr-only">Collection query</span>
          <input value={fixture.query} readOnly placeholder="Describe the collection you want..." />
          <ComposerSymbolButton
            symbol={fixture.isProcessing ? "stop.fill" : "arrow.right"}
            label={fixture.isProcessing ? "Stop" : "Submit"}
            accent
            disabled={!fixture.isProcessing && fixture.query.trim().length === 0}
          />
        </label>
        <ComposerTextButton symbol="xmark.square" label="Clear" />
        <ComposerTextButton symbol="tray.and.arrow.down" label="Save" disabled={!fixture.canSave} />
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
          <ComposerSymbolButton symbol="chevron.down" label="Edit scopes" compact />
        </div>

        <div className="collection-composer-condition-row" aria-label="Collection conditions">
          {fixture.conditions.map((condition) => (
            <ComposerConditionChip
              condition={condition}
              key={condition.id}
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
      {fixture.picker?.kind === "scope" && <ScopePicker picker={fixture.picker} />}

      {fixture.transientFeedback != null && (
        <output className="collection-composer-toast">
          <SFSymbol name="exclamationmark.triangle.fill" size={12} weight={600} />
          {fixture.transientFeedback}
        </output>
      )}
    </section>
  </div>
)

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
}> = ({ symbol, label, disabled }) => (
  <button type="button" className="collection-composer-text-button" disabled={disabled}>
    <SFSymbol name={symbol} size={11} weight={500} />
    {label}
  </button>
)

const ScopePicker: FC<{ readonly picker: ComposerScopePicker }> = ({ picker }) => (
  <dialog className="collection-composer-scope-picker" open aria-label="Scope picker">
    <div className="collection-composer-picker-search">
      <SFSymbol name="magnifyingglass" size={12} />
      <span>{picker.query.length > 0 ? picker.query : "Search directories..."}</span>
    </div>
    <div className="collection-composer-scope-summary">
      <SFSymbol name="scope" size={18} />
      <strong>{picker.currentSummary}</strong>
      <span>Includes subfolders</span>
      <SFSymbol name={picker.includeSubfolders ? "checkmark.circle.fill" : "circle"} size={14} />
    </div>
    {picker.feedback != null && (
      <div className={`collection-composer-scope-feedback ${picker.feedback.phase.toLowerCase()}`}>
        <SFSymbol
          name={
            picker.feedback.phase === "Failed"
              ? "exclamationmark.triangle.fill"
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
        <button type="button" key={item}>
          <SFSymbol name="folder" size={12} />
          {item}
        </button>
      ))}
    </div>
  </dialog>
)
