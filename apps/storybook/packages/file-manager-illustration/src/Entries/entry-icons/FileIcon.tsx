import type { FC } from "react"

export type FileAccent = "blue" | "neutral" | "pdf"
export type FileKind = "doc" | "pdf"

export interface FileIconProps {
  accent?: FileAccent
  decorative?: boolean
  kind?: FileKind
  label: string
}

const DocFileIcon: FC<{ decorative: boolean }> = ({ decorative }) => (
  <svg
    className="entry-svg-icon entry-svg-icon--doc"
    viewBox="0 0 140 180"
    aria-hidden={decorative}
    focusable="false"
  >
    <title>Document icon</title>
    <defs>
      <linearGradient id="doc-paper-grad" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0%" stopColor="var(--fm-entry-paper)" />
        <stop
          offset="100%"
          stopColor="color-mix(in srgb, var(--fm-entry-edge) 30%, var(--fm-entry-paper))"
        />
      </linearGradient>
      <linearGradient id="doc-fold-grad" x1="0" y1="0" x2="1" y2="1">
        <stop
          offset="0%"
          stopColor="color-mix(in srgb, var(--fm-entry-edge) 18%, var(--fm-entry-paper))"
        />
        <stop offset="100%" stopColor="var(--fm-entry-fold)" />
      </linearGradient>
    </defs>
    <path
      d="M 6 15 C 6 10 8 7 11 7 L 93 7 L 140 54 L 140 172 C 140 177 137 180 132 180 L 12 180 C 9 180 6 177 6 172 Z"
      fill="color-mix(in srgb, var(--fm-entry-graphite) 20%, transparent)"
    />
    <path
      d="M 2 11 C 2 6 4 3 7 3 L 89 3 L 136 50 L 136 168 C 136 173 133 176 128 176 L 8 176 C 5 176 2 173 2 168 Z"
      fill="url(#doc-paper-grad)"
      stroke="var(--fm-entry-edge)"
      strokeLinejoin="round"
      strokeWidth="2.5"
    />
    <path
      d="M 89 3 L 89 39 Q 97 47 105 55 L 136 50 Z"
      fill="url(#doc-fold-grad)"
      stroke="var(--fm-entry-edge)"
      strokeLinejoin="round"
      strokeWidth="2.5"
    />
  </svg>
)

export const FileIcon: FC<FileIconProps> = ({
  accent = "neutral",
  decorative = true,
  kind = "doc",
  label,
}) => {
  if (kind === "doc") {
    return <DocFileIcon decorative={decorative} />
  }

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
