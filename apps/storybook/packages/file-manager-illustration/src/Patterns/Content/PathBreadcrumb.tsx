import { type FC, Fragment } from "react"
import { SFSymbol } from "../../Foundations/SFSymbol"
import type { BreadcrumbSegment } from "../../model/types"

export interface PathBreadcrumbProps {
  readonly segments: readonly BreadcrumbSegment[]
}

export const PathBreadcrumb: FC<PathBreadcrumbProps> = ({ segments }) => (
  <nav className="statusbar-breadcrumb" aria-label="Breadcrumb">
    {segments.map((segment, index) => (
      <Fragment
        key={segments
          .slice(0, index + 1)
          .map((item) => item.label)
          .join("/")}
      >
        {index > 0 && (
          <span className="statusbar-chevron-slot">
            <SFSymbol name="chevron.right" size={10} weight={700} />
          </span>
        )}
        <span className="statusbar-breadcrumb-item">
          <SFSymbol name={segment.symbolName} size={14} weight={300} />
          <span className="statusbar-breadcrumb-label">{segment.label}</span>
        </span>
      </Fragment>
    ))}
  </nav>
)

PathBreadcrumb.displayName = "PathBreadcrumb"
