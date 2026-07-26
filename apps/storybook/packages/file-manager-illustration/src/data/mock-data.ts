import type { ContextMenuAction, Entry, FileEntry } from "../model/types"

export const files: readonly Entry[] = [
  { id: "e01", name: "IDC20on20The20Hig...tion.pdf", kind: "pdf" },
  { id: "e02", name: "3_iis_2020_236-244.pdf", kind: "pdf" },
  { id: "e03", name: "Asso for Info Scienc...ior.pdf", kind: "pdf" },
  { id: "e04", name: "Asso for Info Scienc...ion.pdf", kind: "pdf" },
  { id: "e05", name: "Asso for Info Scienc...ure.pdf", kind: "pdf" },
  { id: "e06", name: "fileOrganizationFrom...top.pdf", kind: "pdf" },
  { id: "e07", name: "C04-1083 (1).pdf", kind: "pdf" },
  { id: "e08", name: "thesis_fulltext.pdf", kind: "pdf" },
  { id: "e09", name: "fitchett2014.pdf", kind: "pdf" },
  { id: "e10", name: "View of Usabili...iew.pdf", kind: "pdf" },
  { id: "e20", name: "cursor-brand-assets...924 (1)", kind: "folder" },
  { id: "e23", name: "SCR-20251209-noh.png", kind: "image" },
  { id: "e24", name: "SCR-20251209-new.png", kind: "image" },
  { id: "e53", name: "Voyager waitlist...er.xlsx", kind: "sheet" },
  { id: "e56", name: "privacy-policy-v25.11.27.md", kind: "doc" },
  { id: "e70", name: "Introducing our New Fi...c).mp4", kind: "video" },
  { id: "e40", name: "Windsurf-darwin...5.dmg", kind: "archive" },
]

export const publicFiles: readonly FileEntry[] = files.map((file) => ({
  id: file.id,
  displayName: file.name,
  kind: file.kind,
  extension: null,
  secondaryLabel: file.meta ?? file.count ?? null,
}))

export const selectedInitial: readonly string[] = ["e04", "e05", "e06", "e07", "e08"]

export const imageEntries: readonly Entry[] = [
  { id: "e23", name: "SCR-20251209-noh.png", kind: "image" },
  { id: "e24", name: "SCR-20251209-new.png", kind: "image" },
  { id: "e25", name: "SCR-20251209-noh.png", kind: "image" },
  { id: "e26", name: "SCR-20251209-nou.png", kind: "image" },
  { id: "e27", name: "SCR-20251209-noi.png", kind: "image" },
  { id: "e28", name: "SCR-20251209-noiz.png", kind: "image" },
  { id: "e29", name: "SCR-20251209-nold.png", kind: "image" },
  { id: "e30", name: "SCR-20251209-pmcm.png", kind: "image" },
  { id: "e31", name: "SCR-20251209-pnld.png", kind: "image" },
  { id: "e32", name: "SCR-20251209-pnce.png", kind: "image" },
  { id: "e33", name: "SCR-20251209-pnfg.png", kind: "image" },
  { id: "e34", name: "SCR-20251209-pnity.png", kind: "image" },
]

export const pdfEntries: readonly Entry[] = files.filter((file) => file.kind === "pdf")
export const allSelected: readonly string[] = files.map((file) => file.id)
export const noSelection: readonly string[] = []
export const singleSelection: readonly string[] = ["e04"]

export const entryKindEntries: readonly Entry[] = [
  { id: "e01", name: "IDC20on20The20Hig...tion.pdf", kind: "pdf" },
  { id: "e23", name: "SCR-20251209-noh.png", kind: "image" },
  { id: "e20", name: "cursor-brand-assets...924 (1)", kind: "folder" },
  { id: "e53", name: "Voyager waitlist...er.xlsx", kind: "sheet" },
  { id: "e56", name: "privacy-policy-v25.11.27.md", kind: "doc" },
  { id: "e70", name: "Introducing our New Fi...c).mp4", kind: "video" },
  { id: "e40", name: "Windsurf-darwin...5.dmg", kind: "archive" },
]

export const contextMenuActions: readonly ContextMenuAction[] = [
  { id: "open", label: "Open" },
  { id: "quick-look", label: "Quick Look", shortcut: "Space" },
  { id: "chat", label: "Ask Voyager about selection", shortcut: "⌘⇧A" },
  { id: "delete", label: "Move to Trash", shortcut: "⌘⌫", destructive: true },
]
