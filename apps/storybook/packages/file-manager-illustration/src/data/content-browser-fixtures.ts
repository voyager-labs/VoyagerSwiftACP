import type { FileEntry } from "../model/types"
import { publicFiles } from "./mock-data"

export const contentBrowserFiles: readonly FileEntry[] = publicFiles.slice(0, 16)

export const contentBrowserLongNameFiles: readonly FileEntry[] = [
  {
    id: "long-research-archive",
    displayName:
      "2026-Research-Archive-With-A-Deliberately-Long-Descriptive-Filename-And-Version-History.pdf",
    kind: "pdf",
    extension: "pdf",
    secondaryLabel: "8.4 MB",
  },
  {
    id: "long-field-recording",
    displayName:
      "Field-Recording-Session-Transcript-With-Participants-Locations-And-Follow-Up-Notes.doc",
    kind: "doc",
    extension: "doc",
    secondaryLabel: "Today, 9:41 AM",
  },
  ...contentBrowserFiles.slice(0, 6),
]
