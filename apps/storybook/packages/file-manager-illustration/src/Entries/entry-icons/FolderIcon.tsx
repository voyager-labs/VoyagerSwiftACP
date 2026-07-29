import type { FC } from "react"

export const FolderIcon: FC = () => (
  <svg
    className="entry-svg-icon entry-svg-icon--folder"
    viewBox="0 0 64 64"
    aria-hidden="true"
    focusable="false"
  >
    <title>Folder icon</title>
    <path
      d="M8 53V18.5c0-2.5 2-4.5 4.5-4.5h16.5c1.7 0 3.3.8 4.3 2.2l2.4 3.4h15.3c2.8 0 5 2.2 5 5V53c0 2.8-2.2 5-5 5H13c-2.8 0-5-2.2-5-5z"
      fill="var(--fm-entry-folder-back)"
      stroke="var(--fm-entry-accent-folder)"
      strokeLinejoin="round"
      strokeWidth="0.75"
    />
    <path
      d="M7.5 26.5h49c2.8 0 4.9 2.5 4.4 5.2l-3.3 20.7c-.5 3.3-3.3 5.6-6.6 5.6H12.5c-3.3 0-6.1-2.4-6.6-5.6L3.1 31.7c-.5-2.7 1.6-5.2 4.4-5.2z"
      fill="var(--fm-entry-folder-front)"
      stroke="var(--fm-entry-accent-folder)"
      strokeLinejoin="round"
      strokeWidth="0.75"
    />
    <path
      d="M8.5 29.5h46.7"
      fill="none"
      stroke="var(--fm-entry-folder-highlight)"
      strokeLinecap="round"
      strokeWidth="0.75"
    />
  </svg>
)
