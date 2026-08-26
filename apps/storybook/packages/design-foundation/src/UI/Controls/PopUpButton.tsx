import { type CSSProperties, type FC, useCallback, useId, useRef, useState } from "react"
import type { ControlOption } from "./ControlOption"
import { Menu } from "./Menu"
import { MenuItem } from "./MenuItem"

export interface PopUpButtonProps<Value = string> {
  /** Available options */
  options: readonly ControlOption<Value>[]
  /** Currently selected value */
  value: Value | undefined
  /** Called when the user selects an option */
  onChange: (value: Value) => void
  /** Placeholder text when no option is selected */
  placeholder?: string
  /** Disables interaction */
  disabled?: boolean
  /** Additional class name */
  className?: string
  /** Inline styles */
  style?: CSSProperties
  accessibilityLabel?: string
}

export const PopUpButton: FC<PopUpButtonProps> = <Value,>({
  options,
  value,
  onChange,
  placeholder = "Select…",
  disabled,
  className = "",
  style,
  accessibilityLabel,
}: PopUpButtonProps<Value>) => {
  const [open, setOpen] = useState(false)
  const listboxId = useId()
  const containerRef = useRef<HTMLDivElement>(null)
  const triggerRef = useRef<HTMLButtonElement>(null)

  const selected = options.find((o) => o.value === value)

  const handleTrigger = useCallback(() => {
    if (!disabled) {
      setOpen((prev) => !prev)
    }
  }, [disabled])

  const handleSelect = useCallback(
    (opt: ControlOption<Value>) => {
      if (opt.disabled) return
      onChange(opt.value)
      setOpen(false)
      triggerRef.current?.focus()
    },
    [onChange],
  )

  /** Close on blur if focus leaves the container */
  const handleBlur = useCallback((e: React.FocusEvent<HTMLDivElement>) => {
    if (!containerRef.current?.contains(e.relatedTarget)) {
      setOpen(false)
    }
  }, [])

  /** Close on Escape and restore trigger focus */
  const handleKeyDown = useCallback((e: React.KeyboardEvent<HTMLDivElement>) => {
    if (e.key === "Escape") {
      setOpen(false)
      triggerRef.current?.focus()
    }
  }, [])

  const classes = ["vc-popup", className].filter(Boolean).join(" ")

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
        aria-haspopup="menu"
        aria-expanded={open}
        aria-label={accessibilityLabel ?? selected?.label}
        disabled={disabled}
        className="vc-button vc-popup-trigger"
        onClick={handleTrigger}
      >
        {selected ? (
          <span className="vc-popup-trigger-label">{selected.label}</span>
        ) : (
          <span className="vc-popup-trigger-placeholder">{placeholder}</span>
        )}
      </button>

      {open ? (
        <Menu id={listboxId} className="vc-popup-menu" focusOnMount>
          {options.map((opt) => (
            <MenuItem
              key={String(opt.value)}
              label={opt.label}
              detail={opt.detail}
              role="menuitemradio"
              checked={opt.value === value}
              disabled={opt.disabled}
              onClick={() => handleSelect(opt)}
            />
          ))}
        </Menu>
      ) : null}
    </div>
  )
}

PopUpButton.displayName = "PopUpButton"
