import type { Meta, StoryObj } from "@storybook/react-vite"
import { entryThumbnailFixtures } from "../../data/entry-thumbnail-fixtures"
import type { Entry } from "../../model/types"
import { FileBrowser } from "./FileBrowser"

const entries: readonly Entry[] = [
  {
    id: "e01",
    name: "IDC20on20The20Hig...tion.pdf",
    kind: "pdf",
    thumbnailSrc: entryThumbnailFixtures.pdf,
  },
  {
    id: "e02",
    name: "3_iis_2020_236-244.pdf",
    kind: "pdf",
    thumbnailSrc: entryThumbnailFixtures.pdfTest,
  },
  {
    id: "e03",
    name: "Asso for Info Scienc...ior.pdf",
    kind: "pdf",
    thumbnailSrc: entryThumbnailFixtures.pdf1mb,
  },
  {
    id: "e04",
    name: "Asso for Info Scienc...ion.pdf",
    kind: "pdf",
    thumbnailSrc: entryThumbnailFixtures.pdf150k,
  },
  {
    id: "e05",
    name: "Asso for Info Scienc...ure.pdf",
    kind: "pdf",
    thumbnailSrc: entryThumbnailFixtures.pdfTest,
  },
  {
    id: "e06",
    name: "fileOrganizationFrom...top.pdf",
    kind: "pdf",
    thumbnailSrc: entryThumbnailFixtures.pdf5mb,
  },
  { id: "e07", name: "C04-1083 (1).pdf", kind: "pdf", thumbnailSrc: entryThumbnailFixtures.pdf },
  {
    id: "e08",
    name: "thesis_fulltext.pdf",
    kind: "pdf",
    thumbnailSrc: entryThumbnailFixtures.pdf1mb,
  },
  {
    id: "e09",
    name: "fitchett2014.pdf",
    kind: "pdf",
    thumbnailSrc: entryThumbnailFixtures.pdfTest,
  },
  {
    id: "e10",
    name: "View of Usabili...iew.pdf",
    kind: "pdf",
    thumbnailSrc: entryThumbnailFixtures.pdf150k,
  },
  {
    id: "e20",
    name: "cursor-brand-assets...924 (1)",
    kind: "folder",
    count: "3 items",
    thumbnailSrc: entryThumbnailFixtures.folder,
  },
  {
    id: "e23",
    name: "SCR-20251209-noh.png",
    kind: "image",
    meta: "775 × 396",
    thumbnailSrc: entryThumbnailFixtures.image,
  },
  {
    id: "e24",
    name: "SCR-20251209-new.png",
    kind: "image",
    meta: "717 × 395",
    thumbnailSrc: entryThumbnailFixtures.imageTransparent,
  },
  {
    id: "e25",
    name: "vacation-photo.jpg",
    kind: "image",
    thumbnailSrc: entryThumbnailFixtures.imageJpeg,
  },
  {
    id: "e26",
    name: "hopper.gif",
    kind: "image",
    thumbnailSrc: entryThumbnailFixtures.gif,
  },
  {
    id: "e53",
    name: "Voyager waitlist...er.xlsx",
    kind: "sheet",
    thumbnailSrc: entryThumbnailFixtures.workbook,
  },
  {
    id: "e54",
    name: "monthly-budget.xlsx",
    kind: "sheet",
    thumbnailSrc: entryThumbnailFixtures.workbookBudget,
  },
  {
    id: "e55",
    name: "charts-123233.xlsx",
    kind: "sheet",
    thumbnailSrc: entryThumbnailFixtures.workbookCharts,
  },
  {
    id: "e56",
    name: "privacy-policy-v25.11.27.md",
    kind: "doc",
    thumbnailSrc: entryThumbnailFixtures.text,
  },
  {
    id: "e57",
    name: "checkboxes.docx",
    kind: "doc",
    thumbnailSrc: entryThumbnailFixtures.word,
  },
  {
    id: "e58",
    name: "TestDocument.docx",
    kind: "doc",
    thumbnailSrc: entryThumbnailFixtures.wordTest,
  },
  {
    id: "e59",
    name: "일반 리포트.pages",
    kind: "doc",
    thumbnailSrc: entryThumbnailFixtures.pages,
  },
  {
    id: "e60",
    name: "영상 리포트.pages",
    kind: "doc",
    thumbnailSrc: entryThumbnailFixtures.pagesVideo,
  },
  {
    id: "e61",
    name: "WithTabs.docx",
    kind: "doc",
    thumbnailSrc: entryThumbnailFixtures.wordTabs,
  },
  {
    id: "e62",
    name: "report-59378.docx",
    kind: "doc",
    thumbnailSrc: entryThumbnailFixtures.word59378,
  },
  {
    id: "e63",
    name: "notes-3296.txt",
    kind: "doc",
    thumbnailSrc: entryThumbnailFixtures.text3296,
  },
  {
    id: "e64",
    name: "data-1497.txt",
    kind: "doc",
    thumbnailSrc: entryThumbnailFixtures.text1497,
  },
  {
    id: "e70",
    name: "Introducing our New Fi...c).mp4",
    kind: "video",
    meta: "12:35",
    thumbnailSrc: entryThumbnailFixtures.video,
  },
  {
    id: "e71",
    name: "movie_5.mp4",
    kind: "video",
    thumbnailSrc: entryThumbnailFixtures.videoMovie,
  },
  {
    id: "e72",
    name: "counting.mp4",
    kind: "video",
    thumbnailSrc: entryThumbnailFixtures.videoCounting,
  },
  {
    id: "e65",
    name: "data-46535.xlsx",
    kind: "sheet",
    thumbnailSrc: entryThumbnailFixtures.workbook46535,
  },
  {
    id: "e66",
    name: "notes-259.txt",
    kind: "doc",
    thumbnailSrc: entryThumbnailFixtures.textShort,
  },
  {
    id: "e40",
    name: "Windsurf-darwin...5.dmg",
    kind: "archive",
    meta: "229.2 MB",
    thumbnailSrc: entryThumbnailFixtures.archive,
  },
  {
    id: "e41",
    name: "installer-v2.1.0.zip",
    kind: "archive",
    meta: "85.4 MB",
    thumbnailSrc: entryThumbnailFixtures.archive,
  },
  {
    id: "e21",
    name: "screenshots-2025",
    kind: "folder",
    count: "12 items",
    thumbnailSrc: entryThumbnailFixtures.folder,
  },
  {
    id: "e22",
    name: "design-assets",
    kind: "folder",
    count: "8 items",
    thumbnailSrc: entryThumbnailFixtures.folder,
  },
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
