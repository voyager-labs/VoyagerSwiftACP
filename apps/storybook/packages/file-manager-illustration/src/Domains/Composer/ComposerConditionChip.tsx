import type { FC } from "react"
import { SFSymbol } from "../../Foundations/SFSymbol"
import type { ComposerCondition } from "./composer-fixtures"

export type ComposerConditionChipProps = {
  readonly condition: ComposerCondition
  readonly inactive?: boolean
  readonly showRemove?: boolean
  readonly onOperatorClick?: () => void
  readonly onValueClick?: () => void
}

export const ComposerConditionChip: FC<ComposerConditionChipProps> = ({
  condition,
  inactive,
  showRemove,
  onOperatorClick,
  onValueClick,
}) => (
  <span
    className={`collection-composer-condition-chip${inactive ? " inactive" : ""}${showRemove ? " show-remove" : ""}`}
  >
    <span className="collection-composer-condition-property">
      <SFSymbol name={condition.propertySymbol} size={10} weight={500} />
      {condition.property}
    </span>
    <button
      type="button"
      className="collection-composer-condition-segment"
      onClick={onOperatorClick}
    >
      {condition.operator}
    </button>
    {condition.value.length > 0 && (
      <button
        type="button"
        className="collection-composer-condition-segment"
        onClick={onValueClick}
      >
        {condition.value}
      </button>
    )}
    <button
      type="button"
      className="collection-composer-condition-remove"
      aria-label="Remove condition"
    >
      <SFSymbol name="xmark.circle.fill" size={10} weight={700} />
    </button>
  </span>
)

ComposerConditionChip.displayName = "ComposerConditionChip"
