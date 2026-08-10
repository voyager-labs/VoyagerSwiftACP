import type { FC } from "react"

export const ImageIcon: FC = () => (
  <svg
    className="entry-svg-icon entry-svg-icon--image"
    viewBox="0 0 64 64"
    aria-hidden="true"
    focusable="false"
  >
    <title>Image icon</title>
    <path
      d="M16 5.5h24.5L53 18v35.5c0 3-2.4 5.5-5.5 5.5H16c-3 0-5.5-2.4-5.5-5.5V11c0-3 2.4-5.5 5.5-5.5z"
      fill="color-mix(in srgb, var(--fm-entry-graphite) 12%, transparent)"
    />
    <path
      d="M15 4.5h25L54 18.5V53c0 3-2.4 5.5-5.5 5.5H15c-3 0-5.5-2.4-5.5-5.5V10c0-3 2.4-5.5 5.5-5.5z"
      fill="var(--fm-entry-paper)"
      stroke="var(--fm-entry-edge)"
    />
    <path
      d="M40 4.5v10c0 2.5 1.9 4.5 4.4 4.5H54z"
      fill="color-mix(in srgb, var(--fm-entry-edge) 38%, var(--fm-entry-paper))"
      stroke="var(--fm-entry-edge)"
    />
    <rect
      x="16"
      y="30"
      width="30"
      height="17"
      rx="2"
      fill="color-mix(in srgb, var(--fm-entry-accent-image) 9%, var(--fm-entry-paper))"
      stroke="color-mix(in srgb, var(--fm-entry-accent-image) 42%, var(--fm-entry-edge))"
    />
    <circle
      cx="39.5"
      cy="34.25"
      r="2.25"
      fill="color-mix(in srgb, var(--fm-entry-accent-image) 72%, var(--fm-entry-paper))"
    />
    <path
      d="m18.5 44.75 7.25-7.25 5.1 5.1 4.15-4.15 8.5 6.3z"
      fill="color-mix(in srgb, var(--fm-entry-accent-image) 44%, var(--fm-entry-paper))"
    />
  </svg>
)
