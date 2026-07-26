import type { FC, ReactNode } from "react"

export type FileManagerIconName =
  | "back"
  | "chat"
  | "close"
  | "forward"
  | "grid"
  | "group"
  | "list"
  | "parent"
  | "plus"
  | "send"
  | "sidebar"
  | "sort"

const ICON_PATHS: Readonly<Record<FileManagerIconName, ReactNode>> = {
  back: <path d="m15 18-6-6 6-6" />,
  chat: (
    <>
      <path d="M5 6.5h14v9H9l-4 3v-12Z" />
      <path d="M12 9v4M10 11h4" />
    </>
  ),
  close: <path d="m7 7 10 10M17 7 7 17" />,
  forward: <path d="m9 18 6-6-6-6" />,
  grid: (
    <>
      <rect x="5" y="5" width="5" height="5" rx="1" />
      <rect x="14" y="5" width="5" height="5" rx="1" />
      <rect x="5" y="14" width="5" height="5" rx="1" />
      <rect x="14" y="14" width="5" height="5" rx="1" />
    </>
  ),
  group: (
    <>
      <rect x="5" y="5" width="6" height="6" rx="1" />
      <rect x="13" y="13" width="6" height="6" rx="1" />
    </>
  ),
  list: <path d="M8 6h11M8 12h11M8 18h11M5 6h.01M5 12h.01M5 18h.01" />,
  parent: <path d="m6 15 6-6 6 6" />,
  plus: <path d="M12 5v14M5 12h14" />,
  send: <path d="m5 12 14-7-4 14-3-6-7-1Z" />,
  sidebar: (
    <>
      <rect x="4" y="5" width="16" height="14" rx="2" />
      <path d="M9 5v14" />
    </>
  ),
  sort: <path d="M8 6h11M8 12h8M8 18h5M5 5v14m0 0-2-2m2 2 2-2" />,
}

export interface FileManagerIconProps {
  readonly name: FileManagerIconName
}

export const FileManagerIcon: FC<FileManagerIconProps> = ({ name }) => (
  <svg
    className="fm-symbol-icon"
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    strokeLinecap="round"
    strokeLinejoin="round"
    strokeWidth="1.7"
    aria-hidden="true"
  >
    {ICON_PATHS[name]}
  </svg>
)

FileManagerIcon.displayName = "FileManagerIcon"
