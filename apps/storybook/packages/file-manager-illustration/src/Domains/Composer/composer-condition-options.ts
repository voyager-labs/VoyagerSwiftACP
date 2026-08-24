export type ComposerValueEditor =
  | { readonly kind: "none" }
  | { readonly kind: "text" }
  | { readonly kind: "number"; readonly units?: readonly string[] }
  | { readonly kind: "numberRange"; readonly units?: readonly string[] }
  | { readonly kind: "date" }
  | { readonly kind: "dateRange" }
  | { readonly kind: "boolean" }
  | { readonly kind: "list"; readonly suggestions?: readonly string[] }

export type ComposerOperatorOption = {
  readonly code: string
  readonly label: string
  readonly editor: ComposerValueEditor
}

export type ComposerPropertyOption = {
  readonly key: string
  readonly label: string
  readonly symbol: string
  readonly category: "common" | "date" | "filesystem" | "image" | "video" | "audio" | "misc"
  readonly pinned: boolean
  readonly operators: readonly ComposerOperatorOption[]
}

const textOperators = [
  { code: "cn", label: "Contains", editor: { kind: "text" } },
  { code: "nc", label: "Does not contain", editor: { kind: "text" } },
  { code: "sw", label: "Begins with", editor: { kind: "text" } },
  { code: "ew", label: "Ends with", editor: { kind: "text" } },
  { code: "eq", label: "Is", editor: { kind: "text" } },
  { code: "neq", label: "Is not", editor: { kind: "text" } },
] as const satisfies readonly ComposerOperatorOption[]

const numberEditor = (units?: readonly string[]): ComposerValueEditor =>
  units == null ? { kind: "number" } : { kind: "number", units }

const numberRangeEditor = (units?: readonly string[]): ComposerValueEditor =>
  units == null ? { kind: "numberRange" } : { kind: "numberRange", units }

const numberOperators = (units?: readonly string[]): readonly ComposerOperatorOption[] => [
  { code: "eq", label: "Is", editor: numberEditor(units) },
  { code: "gt", label: "Is greater than", editor: numberEditor(units) },
  { code: "lt", label: "Is less than", editor: numberEditor(units) },
  { code: "btw", label: "Is between", editor: numberRangeEditor(units) },
  { code: "neq", label: "Is not", editor: numberEditor(units) },
  { code: "gte", label: "Is at least", editor: numberEditor(units) },
  { code: "lte", label: "Is at most", editor: numberEditor(units) },
  { code: "nbtw", label: "Is not between", editor: numberRangeEditor(units) },
]

const dateOperators = [
  { code: "eq", label: "Is", editor: { kind: "date" } },
  { code: "neq", label: "Is not", editor: { kind: "date" } },
  { code: "gt", label: "Is greater than", editor: { kind: "date" } },
  { code: "gte", label: "Is at least", editor: { kind: "date" } },
  { code: "lt", label: "Is less than", editor: { kind: "date" } },
  { code: "lte", label: "Is at most", editor: { kind: "date" } },
  { code: "today", label: "Is today", editor: { kind: "none" } },
  { code: "btw", label: "Is between", editor: { kind: "dateRange" } },
  { code: "nbtw", label: "Is not between", editor: { kind: "dateRange" } },
] as const satisfies readonly ComposerOperatorOption[]

const stringListOperators = [
  { code: "any", label: "Contains any", editor: { kind: "list" } },
  { code: "all", label: "Contains all", editor: { kind: "list" } },
  { code: "none", label: "Contains none", editor: { kind: "list" } },
  { code: "miss", label: "Missing any", editor: { kind: "list" } },
  { code: "exists", label: "Exists", editor: { kind: "none" } },
  { code: "empty", label: "Is empty", editor: { kind: "none" } },
] as const satisfies readonly ComposerOperatorOption[]

const categoricalOperators = [
  {
    code: "any",
    label: "Contains any",
    editor: { kind: "list", suggestions: ["PDF", "Document", "Image", "Folder"] },
  },
  {
    code: "none",
    label: "Contains none",
    editor: { kind: "list", suggestions: ["PDF", "Document", "Image", "Folder"] },
  },
  { code: "exists", label: "Exists", editor: { kind: "none" } },
  { code: "empty", label: "Is empty", editor: { kind: "none" } },
] as const satisfies readonly ComposerOperatorOption[]

const booleanOperator = [
  { code: "eq", label: "Is", editor: { kind: "boolean" } },
] as const satisfies readonly ComposerOperatorOption[]

// 네이티브 프로퍼티 세트 번역: Recommended(pinned)는 참고 이미지와 동일한 알파벳 순서로 배치한다
export const composerPropertyOptions = [
  {
    key: "modification_date",
    label: "Content modification date",
    symbol: "calendar",
    category: "date",
    pinned: true,
    operators: dateOperators,
  },
  {
    key: "creation_date",
    label: "Creation date",
    symbol: "calendar.badge.plus",
    category: "date",
    pinned: true,
    operators: dateOperators,
  },
  {
    key: "added_date",
    label: "Date added",
    symbol: "calendar",
    category: "date",
    pinned: true,
    operators: dateOperators,
  },
  {
    key: "extension",
    label: "Extension",
    symbol: "folder",
    category: "filesystem",
    pinned: true,
    operators: categoricalOperators,
  },
  {
    key: "size",
    label: "File size",
    symbol: "arrow.up.left.and.arrow.down.right",
    category: "misc",
    pinned: true,
    operators: numberOperators(["Byte", "KB", "MB", "GB"]),
  },
  {
    key: "name_stem",
    label: "Name",
    symbol: "folder",
    category: "filesystem",
    pinned: true,
    operators: textOperators,
  },
  {
    key: "number_of_pages",
    label: "Number of pages",
    symbol: "doc.text",
    category: "common",
    pinned: false,
    operators: numberOperators(),
  },
  {
    key: "is_invisible",
    label: "Is hidden",
    symbol: "folder",
    category: "filesystem",
    pinned: false,
    operators: booleanOperator,
  },
  {
    key: "keywords",
    label: "Keywords",
    symbol: "list.bullet.rectangle",
    category: "common",
    pinned: false,
    operators: stringListOperators,
  },
  {
    key: "file_kind",
    label: "Kind",
    symbol: "list.bullet.rectangle",
    category: "common",
    pinned: false,
    operators: categoricalOperators,
  },
  {
    key: "title",
    label: "Title",
    symbol: "text.book.closed",
    category: "common",
    pinned: false,
    operators: textOperators,
  },
  {
    key: "creator",
    label: "Creator",
    symbol: "person",
    category: "common",
    pinned: false,
    operators: textOperators,
  },
  {
    key: "last_used_date",
    label: "Last used date",
    symbol: "clock",
    category: "date",
    pinned: false,
    operators: dateOperators,
  },
  {
    key: "pixel_width",
    label: "Pixel width",
    symbol: "arrow.left.and.right",
    category: "image",
    pinned: false,
    operators: numberOperators(),
  },
  {
    key: "pixel_height",
    label: "Pixel height",
    symbol: "rectangle.expand.vertical",
    category: "image",
    pinned: false,
    operators: numberOperators(),
  },
  {
    key: "color_space",
    label: "Color space",
    symbol: "paintpalette",
    category: "image",
    pinned: false,
    operators: textOperators,
  },
  {
    key: "has_alpha_channel",
    label: "Has alpha channel",
    symbol: "circle.lefthalf.filled",
    category: "image",
    pinned: false,
    operators: booleanOperator,
  },
  {
    key: "duration_seconds",
    label: "Duration seconds",
    symbol: "clock",
    category: "common",
    pinned: false,
    operators: numberOperators(),
  },
  {
    key: "video_bit_rate",
    label: "Video bit rate",
    symbol: "waveform.path.ecg",
    category: "video",
    pinned: false,
    operators: numberOperators(),
  },
  {
    key: "audio_bit_rate",
    label: "Audio bit rate",
    symbol: "waveform.path.ecg",
    category: "video",
    pinned: false,
    operators: numberOperators(),
  },
  {
    key: "audio_sample_rate",
    label: "Audio sample rate",
    symbol: "waveform",
    category: "audio",
    pinned: false,
    operators: numberOperators(),
  },
  {
    key: "audio_channel_count",
    label: "Audio channel count",
    symbol: "speaker.wave.2",
    category: "audio",
    pinned: false,
    operators: numberOperators(),
  },
  {
    key: "latitude",
    label: "Latitude",
    symbol: "location",
    category: "image",
    pinned: false,
    operators: textOperators,
  },
  {
    key: "longitude",
    label: "Longitude",
    symbol: "location",
    category: "image",
    pinned: false,
    operators: textOperators,
  },
  {
    key: "content_type_tree",
    label: "Content type tree",
    symbol: "questionmark.circle",
    category: "misc",
    pinned: false,
    operators: textOperators,
  },
] as const satisfies readonly ComposerPropertyOption[]

export const composerPropertyOption = (key: string): ComposerPropertyOption | undefined =>
  composerPropertyOptions.find((property) => property.key === key)
