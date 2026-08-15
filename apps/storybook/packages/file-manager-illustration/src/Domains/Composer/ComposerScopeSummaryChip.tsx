import type { FC } from "react"
import { SFSymbol } from "../../Foundations/SFSymbol"

export type ComposerScopeSummaryChipProps = {
  readonly primary: string
  readonly secondary?: string
  readonly badge?: string
  readonly compact?: boolean
  readonly onEdit?: () => void
}

export const ComposerScopeSummaryChip: FC<ComposerScopeSummaryChipProps> = ({
  primary,
  secondary,
  badge,
  compact,
  onEdit,
}) => (
  <div
    className="collection-composer-scope-summary-chip"
    aria-label={[primary, secondary, badge].filter(Boolean).join(", ")}
  >
    <SFSymbol name="folder" size={10} />
    <span className="collection-composer-scope-summary-copy">
      <strong>{primary}</strong>
      {secondary != null && <small>{secondary}</small>}
    </span>
    {badge != null && <span className="collection-composer-scope-summary-badge">{badge}</span>}
    {onEdit != null && (
      <button
        type="button"
        className={compact ? "compact" : undefined}
        aria-label={`Edit ${primary} scope`}
        onClick={onEdit}
      >
        <SFSymbol name="chevron.down" size={10} />
      </button>
    )}
  </div>
)

ComposerScopeSummaryChip.displayName = "ComposerScopeSummaryChip"
