import type { CSSProperties, FC, ReactNode } from "react"

export interface SheetProps {
  open: boolean
  title: string
  children: ReactNode
  actions?: ReactNode
  size?: "small" | "medium"
  className?: string
  style?: CSSProperties
  onClose: () => void
}

export const Sheet: FC<SheetProps> = ({
  open,
  title,
  children,
  actions,
  size = "small",
  className = "",
  style,
  onClose,
}) => {
  if (!open) return null

  const classes = ["fm-sheet", size, className].filter(Boolean).join(" ")

  return (
    <div className="fm-sheet-backdrop" onMouseDown={onClose}>
      <dialog
        open
        className={classes}
        aria-modal="true"
        aria-label={title}
        style={style}
        onMouseDown={(e) => e.stopPropagation()}
      >
        <div className="fm-sheet-header">
          <h2 className="fm-sheet-title">{title}</h2>
          <button type="button" className="fm-sheet-close" aria-label="Close" onClick={onClose}>
            ✕
          </button>
        </div>
        <div className="fm-sheet-body">{children}</div>
        {actions && <div className="fm-sheet-footer">{actions}</div>}
      </dialog>
    </div>
  )
}

Sheet.displayName = "Sheet"
