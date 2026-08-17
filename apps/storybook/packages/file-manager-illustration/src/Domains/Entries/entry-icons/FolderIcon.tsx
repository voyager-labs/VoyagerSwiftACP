import type { FC } from "react"

export const FolderIcon: FC = () => (
  <svg
    className="entry-svg-icon entry-svg-icon--folder"
    viewBox="0 0 140 140"
    aria-hidden="true"
    focusable="false"
  >
    <title>Folder icon</title>
    <defs>
      <linearGradient id="folder-front-grad" x1="0" y1="0" x2="0" y2="1">
        <stop
          offset="0%"
          stopColor="color-mix(in srgb, var(--fm-entry-folder-front) 78%, var(--fm-entry-paper))"
        />
        <stop offset="100%" stopColor="var(--fm-entry-folder-front)" />
      </linearGradient>
    </defs>
    <path
      d="M 4 126 L 4 36 C 4 24 10 18 18 18 L 47 18 C 56 18 61 26 66 34 L 138.5 34 L 138.5 126 Z"
      fill="color-mix(in srgb, var(--fm-entry-folder-front) 34%, var(--fm-entry-paper))"
      stroke="color-mix(in srgb, var(--fm-entry-accent-folder) 30%, transparent)"
      strokeLinejoin="round"
      strokeWidth="2.5"
    />
    <path
      d="M 8 44 L 8 40 C 10 32 18 28 28 28 L 133.5 28 C 136.5 28 138.5 30 138.5 36 L 138.5 44 Z"
      fill="color-mix(in srgb, var(--fm-entry-folder-front) 18%, var(--fm-entry-paper))"
      stroke="color-mix(in srgb, var(--fm-entry-accent-folder) 20%, transparent)"
      strokeLinejoin="round"
      strokeWidth="1.5"
    />
    <path
      d="M 6 42 C 6 37 10 34 15 34 L 130 34 C 135 34 138.5 37 138.5 42 L 138.5 118 C 138.5 122 135 126 130 126 L 15 126 C 10 126 6 122 6 118 Z"
      fill="url(#folder-front-grad)"
      stroke="color-mix(in srgb, var(--fm-entry-accent-folder) 42%, transparent)"
      strokeLinejoin="round"
      strokeWidth="2.5"
    />
    <path
      d="M 8 36 L 136 36"
      fill="none"
      stroke="var(--fm-entry-folder-highlight)"
      strokeLinecap="round"
      strokeWidth="2.5"
    />
  </svg>
)
