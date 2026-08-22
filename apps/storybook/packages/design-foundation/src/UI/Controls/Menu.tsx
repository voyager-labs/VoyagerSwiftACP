import { type FC, type HTMLAttributes, type KeyboardEvent, useEffect, useRef } from "react"

export interface MenuProps extends Omit<HTMLAttributes<HTMLDivElement>, "role"> {
  /** 열릴 때 checked 항목(없으면 첫 항목)으로 focus를 이동한다 */
  focusOnMount?: boolean
}

export const Menu: FC<MenuProps> = ({ className = "", focusOnMount, ...props }) => {
  const containerRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!focusOnMount) return
    const container = containerRef.current
    const target =
      container?.querySelector<HTMLButtonElement>('button[aria-checked="true"]') ??
      container?.querySelector<HTMLButtonElement>("button")
    target?.focus()
  }, [focusOnMount])

  const handleKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
    props.onKeyDown?.(event)
    if (event.key !== "ArrowDown" && event.key !== "ArrowUp") return
    const items = Array.from(
      containerRef.current?.querySelectorAll<HTMLButtonElement>("button:not(:disabled)") ?? [],
    )
    if (items.length === 0) return
    const currentIndex = items.indexOf(document.activeElement as HTMLButtonElement)
    const nextIndex =
      currentIndex === -1
        ? 0
        : event.key === "ArrowDown"
          ? (currentIndex + 1) % items.length
          : (currentIndex - 1 + items.length) % items.length
    event.preventDefault()
    items[nextIndex]?.focus()
  }

  return (
    <div
      ref={containerRef}
      role="menu"
      className={["fm-menu", className].filter(Boolean).join(" ")}
      {...props}
      onKeyDown={handleKeyDown}
    />
  )
}

Menu.displayName = "Menu"

export const MenuSeparator: FC = () => <div aria-hidden="true" className="fm-menu-separator" />

MenuSeparator.displayName = "MenuSeparator"
