import type { CSSProperties, FC, ReactNode } from "react"

export type PopoverPlacement = "top" | "right" | "bottom" | "left"

export interface PopoverProps {
  open: boolean
  trigger: ReactNode
  children: ReactNode
  placement?: PopoverPlacement
  className?: string
  style?: CSSProperties
  onOpenChange: (open: boolean) => void
}

export const Popover: FC<PopoverProps> = ({
  open,
  trigger,
  children,
  placement = "bottom",
  className = "",
  style,
  onOpenChange,
}) => {
  const classes = ["fm-popover", placement, className].filter(Boolean).join(" ")

  return (
    <span className="fm-popover-wrapper">
      <button
        type="button"
        className="fm-popover-trigger"
        aria-haspopup="true"
        aria-expanded={open}
        onClick={() => onOpenChange(!open)}
      >
        {trigger}
      </button>
      {open && (
        <section className={classes} aria-label="Popover" style={style}>
          {children}
        </section>
      )}
    </span>
  )
}

Popover.displayName = "Popover"
