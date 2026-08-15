import type { FC } from "react"
import { SFSymbol } from "../../Foundations/SFSymbol"
import type { ComposerCondition } from "./composer-fixtures"

export type ComposerConditionChipProps = {
  readonly condition: ComposerCondition
  readonly inactive?: boolean
  readonly showRemove?: boolean
  readonly operatorExpanded?: boolean
  readonly valueExpanded?: boolean
  readonly onPropertyClick?: () => void
  readonly onOperatorClick?: () => void
  readonly onValueClick?: () => void
  readonly onRemove?: () => void
}

export const ComposerConditionChip: FC<ComposerConditionChipProps> = ({
  condition,
  inactive,
  showRemove,
  operatorExpanded,
  valueExpanded,
  onPropertyClick,
  onOperatorClick,
  onValueClick,
  onRemove,
}) => {
  const hasOperator = condition.operator.trim().length > 0
  const valueParts = condition.value.length > 0 ? condition.value.split(" - ") : []

  return (
    <span
      className={`collection-composer-condition-chip${inactive ? " inactive" : ""}${showRemove ? " show-remove" : ""}`}
    >
      <button
        type="button"
        className="collection-composer-condition-property collection-composer-condition-text"
        onClick={onPropertyClick}
      >
        <SFSymbol name={condition.propertySymbol} size={10} weight={500} />
        {condition.property}
      </button>
      <button
        type="button"
        className="collection-composer-condition-segment collection-composer-condition-text"
        aria-expanded={operatorExpanded}
        onClick={onOperatorClick}
      >
        {hasOperator ? condition.operator : "Operator"}
      </button>
      {hasOperator &&
        valueParts.map((part, index) => (
          <span className="collection-composer-condition-value" key={`${index}-${part}`}>
            {index > 0 && (
              <span className="collection-composer-condition-range-sep" aria-hidden="true">
                -
              </span>
            )}
            <button
              type="button"
              className="collection-composer-condition-segment collection-composer-condition-text"
              aria-expanded={valueExpanded}
              onClick={onValueClick}
            >
              {part}
            </button>
          </span>
        ))}
      <button
        type="button"
        className="collection-composer-condition-remove"
        aria-label="Remove condition"
        onClick={onRemove}
      >
        <SFSymbol name="xmark.circle.fill" size={10} weight={700} />
      </button>
    </span>
  )
}

ComposerConditionChip.displayName = "ComposerConditionChip"
