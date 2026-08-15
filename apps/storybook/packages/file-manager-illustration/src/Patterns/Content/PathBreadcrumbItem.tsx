import type { FC } from "react"
import { SFSymbol } from "../../Foundations/SFSymbol"

export interface PathBreadcrumbItemProps {
  readonly label: string
  readonly symbolName: string
}

export const PathBreadcrumbItem: FC<PathBreadcrumbItemProps> = ({ label, symbolName }) => (
  <span className="path-breadcrumb-item">
    <SFSymbol name={symbolName} size={14} />
    <span className="path-breadcrumb-label">{label}</span>
  </span>
)

PathBreadcrumbItem.displayName = "PathBreadcrumbItem"
