import { type CSSProperties, type FC, useCallback, useId, useRef, useState } from "react"
import type { ControlOption } from "./ControlOption"

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
    },
    [onChange],
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
        type="button"
        aria-haspopup="listbox"
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
        <div id={listboxId} className="vc-popup-menu">
          {options.map((opt) => (
            <button
              key={String(opt.value)}
              type="button"
              aria-selected={opt.value === value}
              aria-disabled={opt.disabled || undefined}
              disabled={opt.disabled}
              className={["vc-popup-option", opt.value === value ? "selected" : ""]
                .filter(Boolean)
                .join(" ")}
              onClick={() => handleSelect(opt)}
            >
              <span className="vc-popup-option-label">{opt.label}</span>
              {opt.value === value ? (
                <span className="vc-popup-option-check" aria-hidden="true">
                  ✓
                </span>
              ) : null}
              {opt.detail ? <span className="vc-popup-option-detail">{opt.detail}</span> : null}
            </button>
          ))}
        </div>
      ) : null}
    </div>
  )
}

PopUpButton.displayName = "PopUpButton"
