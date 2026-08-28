import type { FC } from "react"
import { SFSymbol } from "../../Foundations/SFSymbol"
import { displayValueForLiteral } from "./composer-date-literal"
import type { ComposerCondition } from "./composer-fixtures"

export type ComposerConditionChipProps = {
  readonly condition: ComposerCondition
  readonly inactive?: boolean
  readonly showRemove?: boolean
  readonly operatorExpanded?: boolean
  readonly valueExpanded?: boolean
  readonly onPropertyClick?: (id: string) => void
  readonly onOperatorClick?: (id: string) => void
  readonly onValueClick?: (id: string) => void
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
  const hasValue = condition.value.trim().length > 0

  return (
    <span
      className={`collection-composer-condition-chip${inactive ? " inactive" : ""}${showRemove ? " show-remove" : ""}`}
    >
      <button
        type="button"
        className="collection-composer-condition-property collection-composer-condition-text"
        disabled={inactive}
        onClick={() => onPropertyClick?.(condition.id)}
      >
        <SFSymbol name={condition.propertySymbol} size={10} weight={500} />
        <span className="collection-composer-condition-label">{condition.property}</span>
      </button>
      <button
        type="button"
        className="collection-composer-condition-segment collection-composer-condition-text"
        aria-expanded={operatorExpanded}
        disabled={inactive}
        onClick={() => onOperatorClick?.(condition.id)}
      >
        <span className="collection-composer-condition-label">
          {hasOperator ? condition.operator : "Operator"}
        </span>
      </button>
      {hasOperator && hasValue && (
        // 조건 모델에 arity 정보가 없으므로 값 전체를 단일 세그먼트로 렌더한다
        <button
          type="button"
          className="collection-composer-condition-segment collection-composer-condition-text collection-composer-condition-value"
          aria-expanded={valueExpanded}
          disabled={inactive}
          onClick={() => onValueClick?.(condition.id)}
        >
          <span className="collection-composer-condition-label">
            {displayValueForLiteral(condition.value, condition.editorKind)}
          </span>
        </button>
      )}
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
