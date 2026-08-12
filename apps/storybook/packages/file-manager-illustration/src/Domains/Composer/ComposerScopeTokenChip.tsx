import type { FC } from "react"
import { SFSymbol } from "../../Foundations/SFSymbol"

export type ComposerScopeTokenChipProps = {
  readonly title: string
  readonly path?: string
  readonly removable?: boolean
  readonly showRemove?: boolean
}

export const ComposerScopeTokenChip: FC<ComposerScopeTokenChipProps> = ({
  title,
  path,
  removable,
  showRemove,
}) => (
  <span
    className={`collection-composer-scope-token${showRemove ? " show-remove" : ""}`}
    aria-label={path == null ? title : `Scope ${title}, ${path}`}
    title={path ?? title}
  >
    <span className="collection-composer-scope-glyph" aria-hidden="true">
      {"\u{10088A}"}
    </span>
    <span>{title}</span>
    {removable && (
      <button type="button" aria-label={`Remove scope ${title}`}>
        <SFSymbol name="xmark" size={9} weight={500} />
      </button>
    )}
  </span>
)

ComposerScopeTokenChip.displayName = "ComposerScopeTokenChip"
