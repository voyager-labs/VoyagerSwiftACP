import { type FC, Fragment } from "react"
import { SFSymbol } from "../../Foundations/SFSymbol"
import type { BreadcrumbSegment } from "../../model/types"
import { PathBreadcrumbItem } from "./PathBreadcrumbItem"

export interface PathBreadcrumbProps {
  readonly segments: readonly BreadcrumbSegment[]
}

export const PathBreadcrumb: FC<PathBreadcrumbProps> = ({ segments }) => (
  <nav className="path-breadcrumb" aria-label="Breadcrumb">
    {segments.map((segment, index) => (
      <Fragment
        key={segments
          .slice(0, index + 1)
          .map((item) => item.label)
          .join("/")}
      >
        {index > 0 && (
          <span className="path-breadcrumb-chevron">
            <SFSymbol name="chevron.right" size={9} />
          </span>
        )}
        <PathBreadcrumbItem label={segment.label} symbolName={segment.symbolName} />
      </Fragment>
    ))}
  </nav>
)

PathBreadcrumb.displayName = "PathBreadcrumb"
