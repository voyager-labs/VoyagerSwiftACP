import type { Meta, StoryObj } from "@storybook/react-vite"
import type { Entry } from "../model/types"
import { FileBrowser } from "./FileBrowser"

const entries: readonly Entry[] = [
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
  { id: "e20", name: "cursor-brand-assets...924 (1)", kind: "folder", count: "3 items" },
  { id: "e23", name: "SCR-20251209-noh.png", kind: "image", meta: "775 × 396" },
  { id: "e24", name: "SCR-20251209-new.png", kind: "image", meta: "717 × 395" },
  { id: "e53", name: "Voyager waitlist...er.xlsx", kind: "sheet" },
  { id: "e56", name: "privacy-policy-v25.11.27.md", kind: "doc" },
  { id: "e70", name: "Introducing our New Fi...c).mp4", kind: "video", meta: "12:35" },
  { id: "e40", name: "Windsurf-darwin...5.dmg", kind: "archive", meta: "229.2 MB" },
]

const selectedInitial: readonly string[] = ["e04", "e05", "e06", "e07", "e08"]

const meta = {
  component: FileBrowser,
  tags: ["autodocs"],
  parameters: {
    layout: "fullscreen",
  },
  args: {
    entries,
    selectedEntryIds: selectedInitial,
    viewMode: "grid" as const,
    onToggleEntry: () => undefined,
  },
} satisfies Meta<typeof FileBrowser>

export default meta
type Story = StoryObj<typeof meta>

export const Default: Story = {}

export const NarrowChrome: Story = {
  args: {
    viewMode: "grid",
  },
}

export const ListView: Story = {
  args: {
    viewMode: "list",
  },
}
