import type { FC } from "react"
import type { SidebarIconProps } from "../model/types"

export const SidebarIcon: FC<SidebarIconProps> = ({ icon }) => {
  return (
    <span className={`nav-icon ${icon}`} aria-hidden="true">
      {icon === "home" ? (
        <svg viewBox="0 0 18 18" focusable={false} aria-hidden="true">
          <path
            d="M3.25 8.4 9 3.45l5.75 4.95v6.35c0 .7-.55 1.25-1.25 1.25h-2.75v-4.5h-3.5V16H4.5c-.7 0-1.25-.55-1.25-1.25z"
            fill="color-mix(in srgb, currentColor 18%, transparent)"
            stroke="currentColor"
            strokeLinejoin="round"
          />
          <path d="M6.65 16v-4.95h4.7V16" fill="none" stroke="currentColor" />
        </svg>
      ) : icon === "collection" ? (
        <svg viewBox="0 0 18 18" focusable={false} aria-hidden="true">
          <rect
            x="3.75"
            y="5.25"
            width="9.5"
            height="9.5"
            rx="2"
            fill="color-mix(in srgb, currentColor 17%, transparent)"
            stroke="currentColor"
          />
          <path
            d="M5.75 3.25h6.5c1.1 0 2 .9 2 2v6.5"
            fill="none"
            stroke="currentColor"
            strokeLinecap="round"
          />
          <circle cx="7" cy="8" r=".8" fill="currentColor" />
          <circle cx="10.75" cy="8" r=".8" fill="currentColor" />
          <circle cx="8.85" cy="11.5" r=".8" fill="currentColor" />
        </svg>
      ) : icon === "chat" ? (
        <svg viewBox="0 0 18 18" focusable={false} aria-hidden="true">
          <path
            d="M3.25 4.4c0-.85.7-1.55 1.55-1.55h8.4c.85 0 1.55.7 1.55 1.55v5.45c0 .85-.7 1.55-1.55 1.55H8.3l-3.25 3.05v-3.1H4.8c-.85 0-1.55-.7-1.55-1.55z"
            fill="color-mix(in srgb, currentColor 17%, transparent)"
            stroke="currentColor"
            strokeLinejoin="round"
          />
          <path d="M6 6.35h6M6 8.7h4" stroke="currentColor" strokeLinecap="round" />
        </svg>
      ) : (
        <svg viewBox="0 0 18 18" focusable={false} aria-hidden="true">
          <path
            d="M2.5 5.65c0-.8.65-1.45 1.45-1.45h3.6c.45 0 .9.22 1.15.6l.55.8h4.8c.8 0 1.45.65 1.45 1.45v1.05h-13z"
            fill="color-mix(in srgb, currentColor 22%, white)"
            stroke="color-mix(in srgb, currentColor 62%, transparent)"
            strokeLinejoin="round"
          />
          <path
            d="M2 7.55h14c.7 0 1.25.55 1.25 1.25v4.2c0 .8-.65 1.45-1.45 1.45H2.2c-.8 0-1.45-.65-1.45-1.45V8.8c0-.7.55-1.25 1.25-1.25z"
            fill="color-mix(in srgb, currentColor 36%, transparent)"
            stroke="currentColor"
            strokeLinejoin="round"
          />
        </svg>
      )}
    </span>
  )
}

SidebarIcon.displayName = "SidebarIcon"
