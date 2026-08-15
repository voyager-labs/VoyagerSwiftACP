import type { FC } from "react"
import { SFSymbol } from "../../Foundations/SFSymbol"

export type ComposerScopeTokenChipProps = {
  readonly title: string
  readonly path?: string
  readonly removable?: boolean
  readonly showRemove?: boolean
  readonly onRemove?: () => void
}

export const ComposerScopeTokenChip: FC<ComposerScopeTokenChipProps> = ({
  title,
  path,
  removable,
  showRemove,
  onRemove,
}) => (
  <span
    className={`collection-composer-scope-token${showRemove ? " show-remove" : ""}`}
    aria-label={path == null ? title : `Scope ${title}, ${path}`}
    title={path ?? title}
  >
    <span className="collection-composer-scope-glyph" aria-hidden="true">
      {"\u{10088A}"}
    </span>
    <span className="collection-composer-scope-token-title">{title}</span>
    {removable && (
      <button type="button" aria-label={`Remove scope ${title}`} onClick={onRemove}>
        <SFSymbol name="xmark" size={9} weight={500} />
      </button>
    )}
  </span>
)

ComposerScopeTokenChip.displayName = "ComposerScopeTokenChip"
