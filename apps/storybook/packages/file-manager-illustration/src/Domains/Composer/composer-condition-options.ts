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

export const composerPropertyOptions = [
  { key: "name_stem", label: "Name", symbol: "doc.text", operators: textOperators },
  {
    key: "size",
    label: "File size",
    symbol: "arrow.up.left.and.arrow.down.right",
    operators: numberOperators(["Byte", "KB", "MB", "GB"]),
  },
  {
    key: "number_of_pages",
    label: "Number of pages",
    symbol: "doc.richtext",
    operators: numberOperators(),
  },
  {
    key: "modification_date",
    label: "Modified",
    symbol: "calendar.badge.clock",
    operators: dateOperators,
  },
  {
    key: "is_invisible",
    label: "Is hidden",
    symbol: "eye.slash",
    operators: [{ code: "eq", label: "Is", editor: { kind: "boolean" } }],
  },
  {
    key: "keywords",
    label: "Keywords",
    symbol: "text.badge.checkmark",
    operators: stringListOperators,
  },
  { key: "file_kind", label: "Kind", symbol: "tag", operators: categoricalOperators },
] as const satisfies readonly ComposerPropertyOption[]

export const composerPropertyOption = (key: string): ComposerPropertyOption | undefined =>
  composerPropertyOptions.find((property) => property.key === key)
