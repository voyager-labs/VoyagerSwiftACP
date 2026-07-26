import type { FC } from "react"

export interface StatusBarProps {
  selectedLabel: string
  breadcrumb?: string
}

export const StatusBar: FC<StatusBarProps> = ({ selectedLabel, breadcrumb = "" }) => {
  return (
    <footer className="statusbar">
      <nav className="statusbar-breadcrumb" aria-label="Breadcrumb">
        {breadcrumb}
      </nav>
      <span className="statusbar-count">{selectedLabel}</span>
    </footer>
  )
}

StatusBar.displayName = "StatusBar"
