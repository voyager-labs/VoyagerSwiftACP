import type { ButtonHTMLAttributes, FC, ReactNode } from "react"

export interface IconButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  active?: boolean
  children: ReactNode
}

export const IconButton: FC<IconButtonProps> = ({ active, className = "", children, ...props }) => {
  const classes = ["vc-icon-button", active ? "active" : "", className].filter(Boolean).join(" ")

  return (
    <button type="button" className={classes} {...props}>
      {children}
    </button>
  )
}

IconButton.displayName = "IconButton"
