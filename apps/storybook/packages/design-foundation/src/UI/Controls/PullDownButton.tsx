import { type CSSProperties, type FC, useCallback, useId, useRef, useState } from "react"
import type { ControlOption } from "./ControlOption"
import { Menu } from "./Menu"
import { MenuItem } from "./MenuItem"

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
  const triggerRef = useRef<HTMLButtonElement>(null)

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
      triggerRef.current?.focus()
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
        ref={triggerRef}
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
        <Menu id={menuId} className="vc-pulldown-menu" focusOnMount>
          {options.map((opt) => (
            <MenuItem
              key={String(opt.value)}
              label={opt.label}
              detail={opt.detail}
              disabled={opt.disabled}
              onClick={() => handleSelect(opt)}
            />
          ))}
        </Menu>
      ) : null}
    </div>
  )
}

PullDownButton.displayName = "PullDownButton"
