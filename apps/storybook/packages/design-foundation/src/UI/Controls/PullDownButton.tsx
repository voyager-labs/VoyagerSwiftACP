import { type CSSProperties, type FC, useCallback, useId, useRef, useState } from "react"
import type { ControlOption } from "./ControlOption"

export interface PullDownButtonProps<Value = string> {
  /** Action label displayed on the trigger button */
  label: string
  /** Available options */
  options: readonly ControlOption<Value>[]
  /** Called when the user selects an option */
  onSelect: (value: Value) => void
  /** Disables interaction */
  disabled?: boolean
  /** Additional class name */
  className?: string
  /** Inline styles */
  style?: CSSProperties
}

export const PullDownButton: FC<PullDownButtonProps> = <Value,>({
  label,
  options,
  onSelect,
  disabled,
  className = "",
  style,
}: PullDownButtonProps<Value>) => {
  const [open, setOpen] = useState(false)
  const menuId = useId()
  const containerRef = useRef<HTMLDivElement>(null)

  const handleTrigger = useCallback(() => {
    if (!disabled) {
      setOpen((prev) => !prev)
    }
  }, [disabled])

  const handleSelect = useCallback(
    (opt: ControlOption<Value>) => {
      if (opt.disabled) return
      onSelect(opt.value)
      setOpen(false)
    },
    [onSelect],
  )

  /** Close on blur if focus leaves the container */
  const handleBlur = useCallback((e: React.FocusEvent<HTMLDivElement>) => {
    if (!containerRef.current?.contains(e.relatedTarget)) {
      setOpen(false)
    }
  }, [])

  /** Close on Escape */
  const handleKeyDown = useCallback((e: React.KeyboardEvent<HTMLDivElement>) => {
    if (e.key === "Escape") {
      setOpen(false)
    }
  }, [])

  const classes = ["vc-pulldown", className].filter(Boolean).join(" ")

  return (
    <div
      ref={containerRef}
      className={classes}
      style={style}
      onBlur={handleBlur}
      onKeyDown={handleKeyDown}
    >
      <button
        type="button"
        aria-expanded={open}
        aria-haspopup="menu"
        aria-controls={menuId}
        disabled={disabled}
        className="vc-button vc-pulldown-trigger"
        onClick={handleTrigger}
      >
        <span className="vc-pulldown-trigger-label">{label}</span>
      </button>

      {open ? (
        <div id={menuId} className="vc-pulldown-menu" role="menu">
          {options.map((opt) => (
            <button
              key={String(opt.value)}
              type="button"
              role="menuitem"
              aria-disabled={opt.disabled || undefined}
              disabled={opt.disabled}
              className="vc-pulldown-option"
              onClick={() => handleSelect(opt)}
            >
              <span className="vc-pulldown-option-label">{opt.label}</span>
              {opt.detail ? <span className="vc-pulldown-option-detail">{opt.detail}</span> : null}
            </button>
          ))}
        </div>
      ) : null}
    </div>
  )
}

PullDownButton.displayName = "PullDownButton"
