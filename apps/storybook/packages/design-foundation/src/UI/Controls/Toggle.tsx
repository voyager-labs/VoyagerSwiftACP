import type { CSSProperties, FC, ReactNode } from "react"

export interface ToggleProps {
  /** Whether the toggle is on */
  checked: boolean
  /** Called when the user toggles the switch */
  onChange: (checked: boolean) => void
  /** Optional label rendered next to the switch */
  label?: ReactNode
  /** Display size. Default: "regular" */
  size?: "small" | "regular"
  /** Disables interaction */
  disabled?: boolean
  /** Additional class name */
  className?: string
  /** Inline styles */
  style?: CSSProperties
}

export const Toggle: FC<ToggleProps> = ({
  checked,
  onChange,
  label,
  size = "regular",
  disabled,
  className = "",
  style,
}) => {
  const classes = [
    "vc-switch",
    size === "small" ? "vc-switch-small" : "",
    disabled ? "vc-control-disabled" : "",
    className,
  ]
    .filter(Boolean)
    .join(" ")

  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      disabled={disabled}
      className={classes}
      style={style}
      onClick={() => {
        if (!disabled) {
          onChange(!checked)
        }
      }}
    >
      <span className="vc-switch-track" />
      {label ? <span className="vc-switch-label">{label}</span> : null}
    </button>
  )
}

Toggle.displayName = "Toggle"
