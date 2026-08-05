import type { CSSProperties, FC, ReactNode } from "react"

type AlertVariant = "informational" | "warning" | "critical"

export interface AlertProps {
  /** Alert visual severity. */
  variant?: AlertVariant
  /** Brief headline. Required for accessibility landmark context. */
  title: string
  /** Optional supporting detail. */
  message?: string
  /** Optional action buttons rendered below the message. */
  actions?: ReactNode
  /** Additional CSS class names. */
  className?: string
  /** Inline style override. */
  style?: CSSProperties
}

const variantIcons: Record<AlertVariant, string> = {
  informational: "i",
  warning: "!",
  critical: "!",
}

export const Alert: FC<AlertProps> = ({
  variant = "informational",
  title,
  message,
  actions,
  className = "",
  style,
}) => {
  const classes = ["vc-alert", `vc-alert--${variant}`, className].filter(Boolean).join(" ")

  return (
    <div
      className={classes}
      role="alert"
      aria-live={variant === "critical" ? "assertive" : "polite"}
      style={style}
    >
      <span className="vc-alert__icon" aria-hidden="true">
        {variantIcons[variant]}
      </span>
      <div className="vc-alert__body">
        <div className="vc-alert__title">{title}</div>
        {message && <p className="vc-alert__message">{message}</p>}
        {actions && <div className="vc-alert__actions">{actions}</div>}
      </div>
    </div>
  )
}

Alert.displayName = "Alert"