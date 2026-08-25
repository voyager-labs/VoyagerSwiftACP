import type { ButtonHTMLAttributes, FC, ReactNode } from "react"
import { Button } from "./Button"

export interface IconButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  active?: boolean
  bordered?: boolean
  children: ReactNode
}

export const IconButton: FC<IconButtonProps> = ({
  bordered,
  active,
  className = "",
  children,
  ...props
}) => {
  const classes = ["vc-icon-button", active ? "active" : "", bordered ? "bordered" : "", className]
    .filter(Boolean)
    .join(" ")

  return (
    <Button bordered={bordered} className={classes} {...props}>
      {children}
    </Button>
  )
}

IconButton.displayName = "IconButton"
