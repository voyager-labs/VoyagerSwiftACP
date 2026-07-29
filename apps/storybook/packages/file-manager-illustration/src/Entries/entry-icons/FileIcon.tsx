import type { FC } from "react"

export type FileAccent = "blue" | "neutral" | "pdf"
export type FileKind = "doc" | "pdf"

export interface FileIconProps {
  accent?: FileAccent
  decorative?: boolean
  kind?: FileKind
  label: string
}

export const FileIcon: FC<FileIconProps> = ({
  accent = "neutral",
  decorative = true,
  kind = "doc",
  label,
}) => {
  const accentColor =
    accent === "pdf" ? "var(--fm-entry-accent-pdf)" : "var(--fm-entry-accent-document)"

  return (
    <svg
      className={`entry-svg-icon entry-svg-icon--${kind}`}
      viewBox="0 0 64 64"
      aria-hidden={decorative}
      focusable="false"
    >
      <title>{`${kind === "pdf" ? "PDF" : "Document"} icon`}</title>
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
        fill={`color-mix(in srgb, ${accentColor} 15%, var(--fm-entry-paper))`}
        stroke={`color-mix(in srgb, ${accentColor} 34%, var(--fm-entry-edge))`}
        strokeLinejoin="round"
      />
      <text
        x="28"
        y="25.4"
        textAnchor="middle"
        fill={accentColor}
        fontFamily="var(--fm-font-ui)"
        fontSize="7.5"
        fontWeight="700"
        letterSpacing="0.035em"
      >
        {label}
      </text>
      <path
        d="M18 34h22M18 40h20M18 46h15"
        fill="none"
        stroke="var(--fm-entry-rule)"
        strokeLinecap="round"
        strokeWidth="1.4"
      />
    </svg>
  )
}
