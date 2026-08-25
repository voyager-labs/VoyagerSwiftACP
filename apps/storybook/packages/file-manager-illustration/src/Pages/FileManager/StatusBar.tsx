import type { FC } from "react"
import type { BreadcrumbSegment } from "../../model/types"
import { PathBreadcrumb } from "./PathBreadcrumb"

export interface StatusBarProps {
  selectedLabel: string
  breadcrumb?: readonly BreadcrumbSegment[]
}

export const StatusBar: FC<StatusBarProps> = ({ selectedLabel, breadcrumb = [] }) => {
  return (
    <footer className="statusbar">
      <div className="statusbar-breadcrumb">
        <PathBreadcrumb segments={breadcrumb} />
      </div>
      <span className="statusbar-count">{selectedLabel}</span>
    </footer>
  )
}

StatusBar.displayName = "StatusBar"
