import type { FC, ReactNode } from "react"

export interface TooltipProps {
  text: string
  children: ReactNode
}

export const Tooltip: FC<TooltipProps> = ({ text, children }) => {
  return (
    <span className="fm-tooltip" data-tooltip={text}>
      {children}
    </span>
  )
}

Tooltip.displayName = "Tooltip"
