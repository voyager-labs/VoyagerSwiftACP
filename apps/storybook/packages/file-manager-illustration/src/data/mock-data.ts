import type { EntryThumbnailComparisonEntry } from "../Entries/EntryThumbnailComparison"
import type { ContextMenuAction, Entry, FileEntry } from "../model/types"
import { entryThumbnailFixtures } from "./entry-thumbnail-fixtures"

export const files: readonly Entry[] = [
  { id: "e01", name: "IDC20on20The20Hig...tion.pdf", kind: "pdf", thumbnailSrc: entryThumbnailFixtures.pdf },
  { id: "e02", name: "3_iis_2020_236-244.pdf", kind: "pdf", thumbnailSrc: entryThumbnailFixtures.pdfTest },
  { id: "e03", name: "Asso for Info Scienc...ior.pdf", kind: "pdf", thumbnailSrc: entryThumbnailFixtures.pdf1mb },
  { id: "e04", name: "Asso for Info Scienc...ion.pdf", kind: "pdf", thumbnailSrc: entryThumbnailFixtures.pdf150k },
  { id: "e05", name: "Asso for Info Scienc...ure.pdf", kind: "pdf", thumbnailSrc: entryThumbnailFixtures.pdfTest },
  { id: "e06", name: "fileOrganizationFrom...top.pdf", kind: "pdf", thumbnailSrc: entryThumbnailFixtures.pdf5mb },
  { id: "e07", name: "C04-1083 (1).pdf", kind: "pdf", thumbnailSrc: entryThumbnailFixtures.pdf },
  { id: "e08", name: "thesis_fulltext.pdf", kind: "pdf", thumbnailSrc: entryThumbnailFixtures.pdf1mb },
  { id: "e09", name: "fitchett2014.pdf", kind: "pdf", thumbnailSrc: entryThumbnailFixtures.pdfTest },
  { id: "e10", name: "View of Usabili...iew.pdf", kind: "pdf", thumbnailSrc: entryThumbnailFixtures.pdf150k },
  { id: "e20", name: "cursor-brand-assets...924 (1)", kind: "folder", thumbnailSrc: entryThumbnailFixtures.folder },
  { id: "e23", name: "SCR-20251209-noh.png", kind: "image", thumbnailSrc: entryThumbnailFixtures.image },
  { id: "e24", name: "SCR-20251209-new.png", kind: "image", thumbnailSrc: entryThumbnailFixtures.imageJpeg },
  { id: "e53", name: "Voyager waitlist...er.xlsx", kind: "sheet", thumbnailSrc: entryThumbnailFixtures.workbook },
  { id: "e56", name: "privacy-policy-v25.11.27.md", kind: "doc", thumbnailSrc: entryThumbnailFixtures.text },
  { id: "e70", name: "Introducing our New Fi...c).mp4", kind: "video", thumbnailSrc: entryThumbnailFixtures.video },
  { id: "e40", name: "Windsurf-darwin...5.dmg", kind: "archive", thumbnailSrc: entryThumbnailFixtures.archive },

  { id: "e80", name: "sample-local-pdf.pdf", kind: "pdf", thumbnailSrc: entryThumbnailFixtures.pdf },
  { id: "e88", name: "pdf-test.pdf", kind: "pdf", thumbnailSrc: entryThumbnailFixtures.pdfTest },
  {
    id: "e89",
    name: "file-sample_150kB.pdf",
    kind: "pdf",
    thumbnailSrc: entryThumbnailFixtures.pdf150k,
  },
  { id: "e81", name: "hopper.png", kind: "image", thumbnailSrc: entryThumbnailFixtures.image },
  {
    id: "e82",
    name: "transparent.png",
    kind: "image",
    thumbnailSrc: entryThumbnailFixtures.imageTransparent,
  },
  { id: "e83", name: "hopper.jpg", kind: "image", thumbnailSrc: entryThumbnailFixtures.imageJpeg },
  { id: "e84", name: "hopper.gif", kind: "image", thumbnailSrc: entryThumbnailFixtures.gif },
  { id: "e85", name: "checkboxes.docx", kind: "doc", thumbnailSrc: entryThumbnailFixtures.word },
  {
    id: "e86",
    name: "TestDocument.docx",
    kind: "doc",
    thumbnailSrc: entryThumbnailFixtures.wordTest,
  },
  { id: "e87", name: "Booleans.xlsx", kind: "sheet", thumbnailSrc: entryThumbnailFixtures.workbook },
  {
    id: "e90",
    name: "monthly-budget.xlsx",
    kind: "sheet",
    thumbnailSrc: entryThumbnailFixtures.workbookBudget,
  },
  {
    id: "e91",
    name: "일반 리포트.pages",
    kind: "doc",
    thumbnailSrc: entryThumbnailFixtures.pages,
  },
  {
    id: "e92",
    name: "영상 리포트.pages",
    kind: "doc",
    thumbnailSrc: entryThumbnailFixtures.pagesVideo,
  },
  { id: "e93", name: "test-1s.mp4", kind: "video", thumbnailSrc: entryThumbnailFixtures.video },
  { id: "e94", name: "movie_5.mp4", kind: "video", thumbnailSrc: entryThumbnailFixtures.videoMovie },
  { id: "e95", name: "SampleDoc.txt", kind: "doc", thumbnailSrc: entryThumbnailFixtures.text },
  { id: "e96", name: "notes-259.txt", kind: "doc", thumbnailSrc: entryThumbnailFixtures.textShort },

  { id: "e97", name: "WithTabs.docx", kind: "doc", thumbnailSrc: entryThumbnailFixtures.wordTabs },
  { id: "e98", name: "report-59378.docx", kind: "doc", thumbnailSrc: entryThumbnailFixtures.word59378 },
  { id: "e99", name: "charts-123233.xlsx", kind: "sheet", thumbnailSrc: entryThumbnailFixtures.workbookCharts },
  { id: "e100", name: "data-46535.xlsx", kind: "sheet", thumbnailSrc: entryThumbnailFixtures.workbook46535 },
  { id: "e101", name: "counting.mp4", kind: "video", thumbnailSrc: entryThumbnailFixtures.videoCounting },
  { id: "e102", name: "log-3296.txt", kind: "doc", thumbnailSrc: entryThumbnailFixtures.text3296 },
  { id: "e103", name: "data-1497.txt", kind: "doc", thumbnailSrc: entryThumbnailFixtures.text1497 },
  { id: "e104", name: "file-example_1MB.pdf", kind: "pdf", thumbnailSrc: entryThumbnailFixtures.pdf1mb },
  { id: "e105", name: "5mB-sample.pdf", kind: "pdf", thumbnailSrc: entryThumbnailFixtures.pdf5mb },
]

export const publicFiles: readonly FileEntry[] = files.map((file) => ({
  id: file.id,
  displayName: file.name,
  kind: file.kind,
  extension: null,
  secondaryLabel: file.meta ?? file.count ?? null,
  thumbnailSrc: file.thumbnailSrc,
}))

export const selectedInitial: readonly string[] = ["e04", "e05", "e06", "e07", "e08"]

export const imageEntries: readonly Entry[] = [
  { id: "e23", name: "SCR-20251209-noh.png", kind: "image", thumbnailSrc: entryThumbnailFixtures.image },
  { id: "e24", name: "SCR-20251209-new.png", kind: "image", thumbnailSrc: entryThumbnailFixtures.imageJpeg },
  { id: "e25", name: "SCR-20251209-noh.png", kind: "image", thumbnailSrc: entryThumbnailFixtures.imageTransparent },
  { id: "e26", name: "SCR-20251209-nou.png", kind: "image", thumbnailSrc: entryThumbnailFixtures.image },
  { id: "e27", name: "SCR-20251209-noi.png", kind: "image", thumbnailSrc: entryThumbnailFixtures.imageJpeg },
  { id: "e28", name: "SCR-20251209-noiz.png", kind: "image", thumbnailSrc: entryThumbnailFixtures.gif },
  { id: "e29", name: "SCR-20251209-nold.png", kind: "image", thumbnailSrc: entryThumbnailFixtures.image },
  { id: "e30", name: "SCR-20251209-pmcm.png", kind: "image", thumbnailSrc: entryThumbnailFixtures.imageTransparent },
  { id: "e31", name: "SCR-20251209-pnld.png", kind: "image", thumbnailSrc: entryThumbnailFixtures.imageJpeg },
  { id: "e32", name: "SCR-20251209-pnce.png", kind: "image", thumbnailSrc: entryThumbnailFixtures.image },
  { id: "e33", name: "SCR-20251209-pnfg.png", kind: "image", thumbnailSrc: entryThumbnailFixtures.gif },
  { id: "e34", name: "SCR-20251209-pnity.png", kind: "image", thumbnailSrc: entryThumbnailFixtures.image },
]

export const pdfEntries: readonly Entry[] = files.filter((file) => file.kind === "pdf")
export const allSelected: readonly string[] = files.map((file) => file.id)
export const noSelection: readonly string[] = []
export const singleSelection: readonly string[] = ["e04"]

/** 폴백 엔트리 — 모두 PNG 썸네일 사용 */
const pdfFallback: Entry = { id: "e01", name: "IDC20on20The20Hig...tion.pdf", kind: "pdf", thumbnailSrc: entryThumbnailFixtures.pdf }
const imageFallback: Entry = {
  id: "e23",
  name: "SCR-20251209-noh.png",
  kind: "image",
  meta: "775 × 396",
  thumbnailSrc: entryThumbnailFixtures.image,
}
const folderFallback: Entry = {
  id: "e20",
  name: "cursor-brand-assets...924 (1)",
  kind: "folder",
  count: "3 items",
  thumbnailSrc: entryThumbnailFixtures.folder,
}
const sheetFallback: Entry = { id: "e53", name: "Voyager waitlist...er.xlsx", kind: "sheet", thumbnailSrc: entryThumbnailFixtures.workbook }
const docFallback: Entry = { id: "e56", name: "privacy-policy-v25.11.27.md", kind: "doc", thumbnailSrc: entryThumbnailFixtures.text }
const videoFallback: Entry = {
  id: "e70",
  name: "Introducing our New Fi...c).mp4",
  kind: "video",
  meta: "12:35",
  thumbnailSrc: entryThumbnailFixtures.video,
}
const archiveFallback: Entry = {
  id: "e40",
  name: "Windsurf-darwin...5.dmg",
  kind: "archive",
  meta: "229.2 MB",
  thumbnailSrc: entryThumbnailFixtures.archive,
}

/** 미리보기 엔트리(thumbnailSrc 있음) — 명명된 참조 */
const pdfPreview: Entry = {
  id: "e80",
  name: "sample-local-pdf.pdf",
  kind: "pdf",
  thumbnailSrc: entryThumbnailFixtures.pdf,
}
const pdfTestPreview: Entry = {
  id: "e88",
  name: "pdf-test.pdf",
  kind: "pdf",
  thumbnailSrc: entryThumbnailFixtures.pdfTest,
}
const pdfCompactPreview: Entry = {
  id: "e89",
  name: "file-sample_150kB.pdf",
  kind: "pdf",
  thumbnailSrc: entryThumbnailFixtures.pdf150k,
}
const imagePreview: Entry = {
  id: "e81",
  name: "hopper.png",
  kind: "image",
  thumbnailSrc: entryThumbnailFixtures.image,
}
const imageTransparentPreview: Entry = {
  id: "e82",
  name: "transparent.png",
  kind: "image",
  thumbnailSrc: entryThumbnailFixtures.imageTransparent,
}
const imageJpegPreview: Entry = {
  id: "e83",
  name: "hopper.jpg",
  kind: "image",
  thumbnailSrc: entryThumbnailFixtures.imageJpeg,
}
const gifPreview: Entry = {
  id: "e84",
  name: "hopper.gif",
  kind: "image",
  thumbnailSrc: entryThumbnailFixtures.gif,
}
const docPreview: Entry = {
  id: "e95",
  name: "SampleDoc.txt",
  kind: "doc",
  thumbnailSrc: entryThumbnailFixtures.text,
}
const wordPreview: Entry = {
  id: "e85",
  name: "checkboxes.docx",
  kind: "doc",
  thumbnailSrc: entryThumbnailFixtures.word,
}
const wordTestPreview: Entry = {
  id: "e86",
  name: "TestDocument.docx",
  kind: "doc",
  thumbnailSrc: entryThumbnailFixtures.wordTest,
}
const pagesPreview: Entry = {
  id: "e91",
  name: "일반 리포트.pages",
  kind: "doc",
  thumbnailSrc: entryThumbnailFixtures.pages,
}
const pagesVideoPreview: Entry = {
  id: "e92",
  name: "영상 리포트.pages",
  kind: "doc",
  thumbnailSrc: entryThumbnailFixtures.pagesVideo,
}
const sheetPreview: Entry = {
  id: "e87",
  name: "Booleans.xlsx",
  kind: "sheet",
  thumbnailSrc: entryThumbnailFixtures.workbook,
}
const sheetBudgetPreview: Entry = {
  id: "e90",
  name: "monthly-budget.xlsx",
  kind: "sheet",
  thumbnailSrc: entryThumbnailFixtures.workbookBudget,
}
const videoPreview: Entry = {
  id: "e93",
  name: "test-1s.mp4",
  kind: "video",
  thumbnailSrc: entryThumbnailFixtures.video,
}
const videoMoviePreview: Entry = {
  id: "e94",
  name: "movie_5.mp4",
  kind: "video",
  thumbnailSrc: entryThumbnailFixtures.videoMovie,
}
const textShortPreview: Entry = {
  id: "e96",
  name: "notes-259.txt",
  kind: "doc",
  thumbnailSrc: entryThumbnailFixtures.textShort,
}
const wordTabsPreview: Entry = {
  id: "e97",
  name: "WithTabs.docx",
  kind: "doc",
  thumbnailSrc: entryThumbnailFixtures.wordTabs,
}
const word59378Preview: Entry = {
  id: "e98",
  name: "report-59378.docx",
  kind: "doc",
  thumbnailSrc: entryThumbnailFixtures.word59378,
}
const sheetChartsPreview: Entry = {
  id: "e99",
  name: "charts-123233.xlsx",
  kind: "sheet",
  thumbnailSrc: entryThumbnailFixtures.workbookCharts,
}
const sheet46535Preview: Entry = {
  id: "e100",
  name: "data-46535.xlsx",
  kind: "sheet",
  thumbnailSrc: entryThumbnailFixtures.workbook46535,
}
const videoCountingPreview: Entry = {
  id: "e101",
  name: "counting.mp4",
  kind: "video",
  thumbnailSrc: entryThumbnailFixtures.videoCounting,
}
const text3296Preview: Entry = {
  id: "e102",
  name: "log-3296.txt",
  kind: "doc",
  thumbnailSrc: entryThumbnailFixtures.text3296,
}
const text1497Preview: Entry = {
  id: "e103",
  name: "data-1497.txt",
  kind: "doc",
  thumbnailSrc: entryThumbnailFixtures.text1497,
}
const pdf1mbPreview: Entry = {
  id: "e104",
  name: "file-example_1MB.pdf",
  kind: "pdf",
  thumbnailSrc: entryThumbnailFixtures.pdf1mb,
}
const pdf5mbPreview: Entry = {
  id: "e105",
  name: "5mB-sample.pdf",
  kind: "pdf",
  thumbnailSrc: entryThumbnailFixtures.pdf5mb,
}

/**
 * kind별 한 개씩 — 폴백 먼저, 미리보기 다음.
 * EntryList.stories.tsx AllEntryKinds에서 직접 사용.
 */
export const entryKindEntries: readonly (Entry & { meta?: string; count?: string })[] = [
  pdfFallback,
  imageFallback,
  folderFallback,
  sheetFallback,
  docFallback,
  videoFallback,
  archiveFallback,

  pdfPreview,
  pdfTestPreview,
  pdfCompactPreview,
  imagePreview,
  imageTransparentPreview,
  imageJpegPreview,
  gifPreview,
  docPreview,
  wordPreview,
  wordTestPreview,
  pagesPreview,
  pagesVideoPreview,
  sheetPreview,
  sheetBudgetPreview,
  videoPreview,
  videoMoviePreview,
  textShortPreview,

  pdf1mbPreview,
  pdf5mbPreview,
  wordTabsPreview,
  word59378Preview,
  sheetChartsPreview,
  sheet46535Preview,
  videoCountingPreview,
  text3296Preview,
  text1497Preview,
]

/**
 * 스토리 파일에서 사용할 명명된 픽스처.
 * 각 키가 시각적 의도를 나타냄: preview(thumbnailSrc 있음) 또는 fallback.
 */
export const entryStoryFixtures = {
  pdfPreview,
  pdfTestPreview,
  imagePreview,
  imageJpegPreview,
  folderFallback,
  sheetPreview,
  sheetBudgetPreview,
  docPreview,
  wordPreview,
  pagesPreview,
  videoPreview,
  videoMoviePreview,
  archiveFallback,
  imageFallback,
} as const

/**
 * AllKindsAndSizes / AllVariations용 데이터 — 각 kind의 PNG 썸네일 배리에이션.
 */
export const thumbnailComparisonEntries: readonly EntryThumbnailComparisonEntry[] = [
  { id: "e80", kind: "pdf", label: "PDF sample", thumbnailSrc: entryThumbnailFixtures.pdf },
  { id: "e88", kind: "pdf", label: "PDF (test)", thumbnailSrc: entryThumbnailFixtures.pdfTest },
  { id: "e89", kind: "pdf", label: "PDF (150 kB)", thumbnailSrc: entryThumbnailFixtures.pdf150k },
  { id: "e104", kind: "pdf", label: "PDF (1 MB)", thumbnailSrc: entryThumbnailFixtures.pdf1mb },
  { id: "e105", kind: "pdf", label: "PDF (5 MB)", thumbnailSrc: entryThumbnailFixtures.pdf5mb },

  { id: "e81", kind: "image", label: "PNG preview", thumbnailSrc: entryThumbnailFixtures.image },
  {
    id: "e82",
    kind: "image",
    label: "Transparent PNG",
    thumbnailSrc: entryThumbnailFixtures.imageTransparent,
  },
  { id: "e83", kind: "image", label: "JPEG preview", thumbnailSrc: entryThumbnailFixtures.imageJpeg },
  { id: "e84", kind: "image", label: "GIF preview", thumbnailSrc: entryThumbnailFixtures.gif },

  {
    id: "e20t",
    kind: "folder",
    label: "Folder icon",
    thumbnailSrc: entryThumbnailFixtures.folder,
  },

  {
    id: "e87",
    kind: "sheet",
    label: "XLSX preview",
    thumbnailSrc: entryThumbnailFixtures.workbook,
  },
  {
    id: "e90",
    kind: "sheet",
    label: "XLSX (budget)",
    thumbnailSrc: entryThumbnailFixtures.workbookBudget,
  },
  {
    id: "e99",
    kind: "sheet",
    label: "XLSX (charts)",
    thumbnailSrc: entryThumbnailFixtures.workbookCharts,
  },
  {
    id: "e100",
    kind: "sheet",
    label: "XLSX (data)",
    thumbnailSrc: entryThumbnailFixtures.workbook46535,
  },

  { id: "e95", kind: "doc", label: "TXT preview", thumbnailSrc: entryThumbnailFixtures.text },
  { id: "e96", kind: "doc", label: "TXT (short)", thumbnailSrc: entryThumbnailFixtures.textShort },
  { id: "e102", kind: "doc", label: "TXT (log)", thumbnailSrc: entryThumbnailFixtures.text3296 },
  { id: "e103", kind: "doc", label: "TXT (data)", thumbnailSrc: entryThumbnailFixtures.text1497 },
  { id: "e85", kind: "doc", label: "DOCX preview", thumbnailSrc: entryThumbnailFixtures.word },
  {
    id: "e86",
    kind: "doc",
    label: "DOCX (test)",
    thumbnailSrc: entryThumbnailFixtures.wordTest,
  },
  { id: "e97", kind: "doc", label: "DOCX (tabs)", thumbnailSrc: entryThumbnailFixtures.wordTabs },
  {
    id: "e98",
    kind: "doc",
    label: "DOCX (report)",
    thumbnailSrc: entryThumbnailFixtures.word59378,
  },
  { id: "e91", kind: "doc", label: "Pages preview", thumbnailSrc: entryThumbnailFixtures.pages },
  {
    id: "e92",
    kind: "doc",
    label: "Pages (video)",
    thumbnailSrc: entryThumbnailFixtures.pagesVideo,
  },

  { id: "e93", kind: "video", label: "Video preview", thumbnailSrc: entryThumbnailFixtures.video },
  {
    id: "e94",
    kind: "video",
    label: "Video (movie)",
    thumbnailSrc: entryThumbnailFixtures.videoMovie,
  },
  {
    id: "e101",
    kind: "video",
    label: "Video (counting)",
    thumbnailSrc: entryThumbnailFixtures.videoCounting,
  },

  {
    id: "e40t",
    kind: "archive",
    label: "Archive icon",
    thumbnailSrc: entryThumbnailFixtures.archive,
  },
]

export const contextMenuActions: readonly ContextMenuAction[] = [
  { id: "open", label: "Open" },
  { id: "quick-look", label: "Quick Look", shortcut: "Space" },
  { id: "chat", label: "Ask Voyager about selection", shortcut: "⌘⇧A" },
  { id: "delete", label: "Move to Trash", shortcut: "⌘⌫", destructive: true },
]
