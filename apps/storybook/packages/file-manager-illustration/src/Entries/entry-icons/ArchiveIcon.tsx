import type { FC } from "react"

export const ArchiveIcon: FC = () => (
  <svg
    className="entry-svg-icon entry-svg-icon--archive"
    viewBox="0 0 64 80"
    aria-hidden="true"
    focusable="false"
  >
    <title>Archive icon</title>
    <defs>
      <linearGradient id="archive-paper-grad" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0%" stopColor="var(--fm-entry-paper)" />
        <stop
          offset="100%"
          stopColor="color-mix(in srgb, var(--fm-entry-edge) 24%, var(--fm-entry-paper))"
        />
      </linearGradient>
    </defs>
    <path
      d="M14 3h22l14 14v57c0 3.3-2.7 6-6 6H14c-3.3 0-6-2.7-6-6V9c0-3.3 2.7-6 6-6z"
      fill="url(#archive-paper-grad)"
      stroke="var(--fm-entry-edge)"
      strokeLinejoin="round"
      strokeWidth="1.25"
    />
    <path
      d="M36 3v9c0 1.7 1.3 3 3 3h11z"
      fill="var(--fm-entry-fold)"
      stroke="var(--fm-entry-edge)"
      strokeLinejoin="round"
      strokeWidth="1.25"
    />
    <rect x="27" y="12" width="10" height="52" rx="1.5" fill="var(--fm-entry-graphite)" />
    <g stroke="var(--fm-entry-paper)" strokeWidth="1.4" strokeLinecap="round">
      <line x1="27" y1="17" x2="37" y2="17" />
      <line x1="27" y1="22" x2="37" y2="22" />
      <line x1="27" y1="27" x2="37" y2="27" />
      <line x1="27" y1="32" x2="37" y2="32" />
      <line x1="27" y1="37" x2="37" y2="37" />
      <line x1="27" y1="42" x2="37" y2="42" />
      <line x1="27" y1="47" x2="37" y2="47" />
    </g>
    <rect x="25" y="52" width="14" height="8" rx="1.5" fill="var(--fm-entry-graphite)" />
    <rect x="28" y="50" width="8" height="4" rx="1" fill="var(--fm-entry-graphite)" />
    <rect x="30" y="54" width="4" height="3" rx="0.5" fill="var(--fm-entry-paper)" opacity="0.7" />
  </svg>
)
