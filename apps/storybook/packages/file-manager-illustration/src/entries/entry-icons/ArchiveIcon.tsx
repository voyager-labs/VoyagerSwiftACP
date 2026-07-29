import type { FC } from "react"

export const ArchiveIcon: FC = () => (
  <svg
    className="entry-svg-icon entry-svg-icon--archive"
    viewBox="0 0 64 64"
    aria-hidden="true"
    focusable="false"
  >
    <title>Archive icon</title>
    <path
      d="M16 5h22l12 12v35c0 3.3-2.7 6-6 6H16c-3.3 0-6-2.7-6-6V11c0-3.3 2.7-6 6-6z"
      fill="var(--fm-entry-paper)"
      stroke="var(--fm-entry-edge)"
      strokeLinejoin="round"
      strokeWidth="1.25"
    />
    <path
      d="M38 5v9c0 1.7 1.3 3 3 3h9z"
      fill="var(--fm-entry-fold)"
      stroke="var(--fm-entry-edge)"
      strokeLinejoin="round"
      strokeWidth="1.25"
    />
    <path d="M28 19.5h8v15.5c0 2.2-1.8 4-4 4s-4-1.8-4-4z" fill="var(--fm-entry-graphite)" />
    <path
      d="M28 23h8M28 28h8M28 33h8"
      fill="none"
      stroke="var(--fm-entry-paper)"
      strokeLinecap="round"
      strokeWidth="1.5"
    />
    <path d="M27 38.5h10v4.5c0 1.1-.9 2-2 2h-6c-1.1 0-2-.9-2-2z" fill="var(--fm-entry-graphite)" />
    <path
      d="M16 46h30V57H16z"
      fill="color-mix(in srgb, var(--fm-entry-accent-archive) 14%, var(--fm-entry-paper))"
      stroke="color-mix(in srgb, var(--fm-entry-accent-archive) 44%, var(--fm-entry-edge))"
      strokeLinejoin="round"
    />
    <text
      x="31"
      y="56"
      textAnchor="middle"
      fill="var(--fm-entry-graphite)"
      fontFamily="var(--fm-font-ui)"
      fontSize="13"
      fontWeight="700"
      letterSpacing="0.02em"
    >
      ZIP
    </text>
  </svg>
)
