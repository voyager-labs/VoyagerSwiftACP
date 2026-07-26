import type { ButtonHTMLAttributes, FC, ReactNode } from "react"

type ButtonVariant = "default" | "primary" | "subtle" | "destructive"

export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant
  loading?: boolean
  pill?: boolean
  children: ReactNode
}

export const Button: FC<ButtonProps> = ({
  variant = "default",
  loading,
  pill,
  className = "",
  children,
  ...props
}) => {
  const classes = [
    "vc-button",
    variant !== "default" ? variant : "",
    pill ? "pill" : "",
    loading ? "loading" : "",
    className,
  ]
    .filter(Boolean)
    .join(" ")

  return (
    <button type="button" className={classes} {...props}>
      {children}
    </button>
  )
}

Button.displayName = "Button"
