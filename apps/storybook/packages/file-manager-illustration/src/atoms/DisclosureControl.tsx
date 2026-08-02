import type { ButtonHTMLAttributes, FC, ReactNode } from "react"

export interface DisclosureControlProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  expanded: boolean
  onToggle: () => void
  buttonStyle?: boolean
  children: ReactNode
}

export const DisclosureControl: FC<DisclosureControlProps> = ({
  expanded,
  onToggle,
  buttonStyle,
  className = "",
  children,
  ...props
}) => {
  const classes = ["vc-disclosure", buttonStyle ? "button-style" : "", className]
    .filter(Boolean)
    .join(" ")

  return (
    <button
      type="button"
      className={classes}
      aria-expanded={expanded}
      onClick={onToggle}
      {...props}
    >
      <span className="vc-disclosure-marker">&gt;</span>
      {children}
    </button>
  )
}

DisclosureControl.displayName = "DisclosureControl"
