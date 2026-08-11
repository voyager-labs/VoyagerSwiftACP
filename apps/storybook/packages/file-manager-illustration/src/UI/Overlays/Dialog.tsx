import type { CSSProperties, FC, ReactNode } from "react"

export interface DialogProps {
  open: boolean
  title: string
  children: ReactNode
  actions?: ReactNode
  size?: "small" | "medium"
  className?: string
  style?: CSSProperties
  onClose: () => void
}

export const Dialog: FC<DialogProps> = ({
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

  const classes = ["fm-dialog", size, className].filter(Boolean).join(" ")

  return (
    <div className="fm-overlay-backdrop" onMouseDown={onClose}>
      <dialog
        className={classes}
        open
        aria-label={title}
        style={style}
        onMouseDown={(e) => e.stopPropagation()}
      >
        <div className="fm-dialog-header">
          <h2 className="fm-dialog-title">{title}</h2>
          <button type="button" className="fm-dialog-close" aria-label="Close" onClick={onClose}>
            ✕
          </button>
        </div>
        <div className="fm-dialog-body">{children}</div>
        {actions && <div className="fm-dialog-footer">{actions}</div>}
      </dialog>
    </div>
  )
}

Dialog.displayName = "Dialog"
