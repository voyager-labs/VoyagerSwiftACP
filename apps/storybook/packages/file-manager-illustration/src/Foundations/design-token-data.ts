export type TokenSpec = {
  readonly name: `--${string}`
  readonly label: string
  readonly source?: `--${string}`
}

export const colorTokens = [
  { name: "--fm-window", label: "Window", source: "--macos-window-background-color" },
  { name: "--fm-sidebar", label: "Sidebar", source: "--macos-material-sidebar" },
  { name: "--fm-toolbar", label: "Toolbar", source: "--macos-material-header-view" },
  { name: "--fm-content", label: "Content", source: "--macos-material-content-background" },
  { name: "--fm-inspector", label: "Inspector", source: "--macos-material-sheet" },
  {
    name: "--fm-statusbar",
    label: "Status bar",
    source: "--macos-material-under-window-background",
  },
  { name: "--fm-text-primary", label: "Primary text", source: "--macos-label-color" },
  { name: "--fm-text-secondary", label: "Secondary text", source: "--macos-secondary-label-color" },
  {
    name: "--fm-selection",
    label: "Selection",
    source: "--macos-unemphasized-selected-content-background-color",
  },
  {
    name: "--fm-selection-strong",
    label: "Strong selection",
    source: "--macos-selected-content-background-color",
  },
  { name: "--fm-separator", label: "Separator", source: "--macos-separator-color" },
  {
    name: "--fm-focus-ring",
    label: "Focus ring",
    source: "--macos-keyboard-focus-indicator-color",
  },
] as const satisfies readonly TokenSpec[]

export const accentTokens = [
  { name: "--fm-blue", label: "Blue", source: "--macos-system-blue" },
  { name: "--fm-folder", label: "Cyan", source: "--macos-system-cyan" },
  { name: "--fm-green", label: "Green", source: "--macos-system-green" },
  { name: "--fm-amber", label: "Orange", source: "--macos-system-orange" },
  { name: "--fm-red", label: "Red", source: "--macos-system-red" },
  { name: "--fm-yellow", label: "Yellow", source: "--macos-system-yellow" },
] as const satisfies readonly TokenSpec[]

export const swiftUIColorTokens = [
  { name: "--swiftui-primary", label: "Primary" },
  { name: "--swiftui-secondary", label: "Secondary" },
  { name: "--swiftui-accent-color", label: "Accent color" },
  { name: "--swiftui-black", label: "Black" },
  { name: "--swiftui-white", label: "White" },
  { name: "--swiftui-clear", label: "Clear" },
  { name: "--swiftui-blue", label: "Blue" },
  { name: "--swiftui-brown", label: "Brown" },
  { name: "--swiftui-cyan", label: "Cyan" },
  { name: "--swiftui-gray", label: "Gray" },
  { name: "--swiftui-green", label: "Green" },
  { name: "--swiftui-indigo", label: "Indigo" },
  { name: "--swiftui-mint", label: "Mint" },
  { name: "--swiftui-orange", label: "Orange" },
  { name: "--swiftui-pink", label: "Pink" },
  { name: "--swiftui-purple", label: "Purple" },
  { name: "--swiftui-red", label: "Red" },
  { name: "--swiftui-teal", label: "Teal" },
  { name: "--swiftui-yellow", label: "Yellow" },
] as const satisfies readonly TokenSpec[]

export const materialTokens = [
  { name: "--fm-sidebar", label: "Sidebar", source: "--macos-material-sidebar" },
  { name: "--fm-toolbar", label: "Header view", source: "--macos-material-header-view" },
  { name: "--fm-inspector", label: "Sheet", source: "--macos-material-sheet" },
  { name: "--fm-elevated", label: "Popover", source: "--macos-material-popover" },
  {
    name: "--fm-statusbar",
    label: "Under window",
    source: "--macos-material-under-window-background",
  },
] as const satisfies readonly TokenSpec[]

export const typeTokens = [
  { name: "--fm-font-size-caption-2", label: "Caption 2" },
  { name: "--fm-font-size-caption", label: "Caption" },
  { name: "--fm-font-size-body", label: "Body" },
  { name: "--fm-font-size-title", label: "Title" },
] as const satisfies readonly TokenSpec[]

export const radiusTokens = [
  { name: "--fm-radius-xs", label: "Extra small" },
  { name: "--fm-radius-sm", label: "Small" },
  { name: "--fm-radius-md", label: "Medium" },
  { name: "--fm-radius-lg", label: "Large" },
  { name: "--fm-radius-xl", label: "Extra large" },
  { name: "--fm-radius-window", label: "Window" },
] as const satisfies readonly TokenSpec[]

export const spacingTokens = [
  { name: "--fm-space-2", label: "Space 2" },
  { name: "--fm-space-4", label: "Space 4" },
  { name: "--fm-space-6", label: "Space 6" },
  { name: "--fm-space-8", label: "Space 8" },
  { name: "--fm-space-9", label: "Space 9" },
  { name: "--fm-space-10", label: "Space 10" },
] as const satisfies readonly TokenSpec[]

export const shadowTokens = [
  { name: "--fm-shadow-paper", label: "Paper" },
  { name: "--fm-shadow-card", label: "Card" },
  { name: "--fm-shadow-window", label: "Window" },
] as const satisfies readonly TokenSpec[]

export const tokenNames: readonly string[] = [
  ...colorTokens,
  ...accentTokens,
  ...swiftUIColorTokens,
  ...materialTokens,
  ...typeTokens,
  ...radiusTokens,
  ...spacingTokens,
  ...shadowTokens,
].map((token) => token.name)
