import { type FC, Fragment } from "react"
import { SFSymbol } from "../Foundations/SFSymbol"
import type { BreadcrumbSegment } from "../model/types"

export interface StatusBarProps {
  selectedLabel: string
  breadcrumb?: readonly BreadcrumbSegment[]
}

export const StatusBar: FC<StatusBarProps> = ({ selectedLabel, breadcrumb = [] }) => {
  return (
    <footer className="statusbar">
      <nav className="statusbar-breadcrumb" aria-label="Breadcrumb">
        {breadcrumb.map((segment, index) => (
          <Fragment
            key={breadcrumb
              .slice(0, index + 1)
              .map((s) => s.label)
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
      <span className="statusbar-count">{selectedLabel}</span>
    </footer>
  )
}

StatusBar.displayName = "StatusBar"
