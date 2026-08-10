import type { FC } from "react"

export interface SheetIconProps {
  decorative?: boolean
}

export const SheetIcon: FC<SheetIconProps> = ({ decorative = true }) => (
  <svg
    className="entry-svg-icon entry-svg-icon--sheet"
    viewBox="0 0 64 64"
    aria-hidden={decorative}
    focusable="false"
  >
    <title>Spreadsheet icon</title>
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
    <path
      d="M18 19h20v9H18z"
      fill="color-mix(in srgb, var(--fm-entry-accent-sheet) 15%, var(--fm-entry-paper))"
      stroke="color-mix(in srgb, var(--fm-entry-accent-sheet) 34%, var(--fm-entry-edge))"
      strokeLinejoin="round"
    />
    <text
      x="28"
      y="25.4"
      textAnchor="middle"
      fill="var(--fm-entry-accent-sheet)"
      fontFamily="var(--fm-font-ui)"
      fontSize="7.5"
      fontWeight="700"
      letterSpacing="0.035em"
    >
      XLS
    </text>
    <rect
      x="18"
      y="34"
      width="25"
      height="14"
      rx="1.5"
      fill="color-mix(in srgb, var(--fm-entry-accent-sheet) 8%, var(--fm-entry-paper))"
      stroke="color-mix(in srgb, var(--fm-entry-accent-sheet) 34%, var(--fm-entry-rule))"
    />
    <path
      d="M18 38.7h25M18 43.3h25M26.3 34v14M34.7 34v14"
      fill="none"
      stroke="var(--fm-entry-rule)"
      strokeWidth="1.2"
    />
  </svg>
)
