import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { dirname, resolve } from "node:path"
import { fileURLToPath } from "node:url"
import { createElement } from "react"
import { renderToStaticMarkup } from "react-dom/server"
import * as runtime from "../dist/index.js"
import { verifyChatInteractionContract } from "./verify-chat-interaction-contract.mjs"
import { verifyChatMessageContract } from "./verify-chat-message-contract.mjs"
import { verifyDesignVersionContract } from "./verify-design-version-contract.mjs"
import { verifyThumbnailFixtures } from "./verify-thumbnail-fixtures.mjs"

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..")
const storybookRoot = resolve(packageRoot, "../..")
const macosTokens = readFileSync(resolve(packageRoot, "src/styles/macos-tokens.css"), "utf8")
const generatedMaterialMetadata = readFileSync(
  resolve(packageRoot, "src/Foundations/swiftui-material-metadata.generated.ts"),
  "utf8",
)
const styleSheets = [
  "src/styles/file-manager.css",
  "src/styles/atoms.css",
  "src/styles/window-shell.css",
  "src/styles/sidebar.css",
  "src/styles/inspector.css",
]
const fileManagerCss = readFileSync(resolve(packageRoot, styleSheets[0]), "utf8")
const css = [
  macosTokens,
  ...styleSheets.map((path) => readFileSync(resolve(packageRoot, path), "utf8")),
].join("\n")
const sourceBarrel = readFileSync(resolve(packageRoot, "src/index.ts"), "utf8")
const designTokensStorySource = readFileSync(
  resolve(packageRoot, "src/Foundations/DesignTokens.stories.tsx"),
  "utf8",
)
const packageJson = JSON.parse(readFileSync(resolve(packageRoot, "package.json"), "utf8"))
const index = JSON.parse(
  readFileSync(resolve(storybookRoot, "storybook-static/index.json"), "utf8"),
)

const tabs = [
  { id: "home", label: "Home" },
  { id: "directory", label: "Directory" },
]

const files = [
  {
    id: "entry-1",
    displayName: "Report.pdf",
    kind: "pdf",
    extension: "pdf",
    secondaryLabel: null,
  },
]

function render(activeTabId) {
  return renderToStaticMarkup(
    createElement(runtime.FileManagerIllustration, {
      files,
      contentContext: { tabs, activeTabId },
    }),
  )
}

function renderChatSurface(chatSurface) {
  return renderToStaticMarkup(
    createElement(runtime.FileManagerIllustration, {
      files,
      contentContext: { tabs, activeTabId: "directory" },
      chatSurface,
    }),
  )
}

const readyEmptyInputBar = {
  placeholder: "Ask anything…",
  inputAccessibilityLabel: "Chat message",
  inputAccessibilityHint: "Enter to send, Shift+Enter for new line",
  contextAffordanceLabel: "Add attachment",
  modelSelector: {
    label: "GPT-5.2",
    accessibilityLabel: "Model",
    accessibilityValue: "GPT-5.2",
    isDisabled: false,
    value: "gpt-5.2",
    options: [{ value: "gpt-5.2", label: "GPT-5.2", disabled: false }],
  },
  thinkingSelector: {
    label: "Thinking",
    accessibilityLabel: "Thinking",
    accessibilityValue: "No selection",
    isDisabled: false,
    value: "no-selection",
    options: [{ value: "no-selection", label: "No selection", disabled: false }],
  },
  action: {
    kind: "submit",
    isEnabled: false,
    accessibilityLabel: "Send",
    help: "Enter to send, Shift+Enter for new line",
  },
  isComposerEditingDisabled: false,
  contextSections: [],
}

const directoryMarkup = render("directory")
const homeMarkup = render("home")
const unconnectedMarkup = renderChatSurface({
  kind: "unconnected",
  inputBar: {
    placeholder: "Ask anything…",
    inputAccessibilityLabel: "Chat message",
    inputAccessibilityHint: "Enter to send, Shift+Enter for new line",
    contextAffordanceLabel: "Add attachment",
    modelSelector: {
      label: "No models",
      accessibilityLabel: "Model",
      accessibilityValue: "No models",
      isDisabled: true,
      value: "no-models",
      options: [{ value: "no-models", label: "No models", disabled: true }],
    },
    thinkingSelector: {
      label: "Thinking",
      accessibilityLabel: "Thinking",
      accessibilityValue: "No selection",
      isDisabled: true,
      value: "no-selection",
      options: [{ value: "no-selection", label: "No selection", disabled: true }],
    },
    action: {
      kind: "submit",
      isEnabled: false,
      accessibilityLabel: "Send",
      help: "Enter to send, Shift+Enter for new line",
    },
    isComposerEditingDisabled: false,
    contextSections: [],
  },
  connectionError: {
    title: "Connect an AI provider",
    detail: "Set up a provider in Settings to chat with this context.",
    actionLabel: "Open Settings",
  },
})

assert.match(directoryMarkup, /aria-label="Sidebar"/)
assert.match(directoryMarkup, /aria-label="Entries"/)
assert.match(directoryMarkup, /aria-label="Breadcrumb"/)
assert.match(directoryMarkup, /role="separator"/)
assert.doesNotMatch(directoryMarkup, /window-chrome|window-title/)
assert.ok(
  directoryMarkup.indexOf("traffic-lights") > directoryMarkup.indexOf('aria-label="Sidebar"'),
)
assert.match(homeMarkup, /aria-label="Home"/)
assert.doesNotMatch(homeMarkup, /aria-label="Entries"/)
assert.match(unconnectedMarkup, /Connect an AI provider/)
assert.match(unconnectedMarkup, /Set up a provider in Settings to chat with this context\./)
assert.match(unconnectedMarkup, /Open Settings/)
assert.match(unconnectedMarkup, /class="chat-transcript"/)
assert.doesNotMatch(unconnectedMarkup, /class="chat-empty"/)
assert.match(unconnectedMarkup, /No models/)
assert.match(unconnectedMarkup, /aria-label="AI provider status"/)
assert.ok(
  unconnectedMarkup.indexOf('aria-label="AI provider status"') <
    unconnectedMarkup.indexOf('aria-label="Chat message"'),
)
assert.match(unconnectedMarkup, /<select[^>]*disabled[^>]*aria-label="Model: No models"/)
assert.match(unconnectedMarkup, /<select[^>]*disabled[^>]*aria-label="Thinking: No selection"/)
assert.doesNotMatch(unconnectedMarkup, /GPT-5\.2/)

/* ── 채팅 surface 상태 매트릭스: inspector empty / centered / connectionError / rebind ── */

const inspectorEmptyMarkup = renderChatSurface({
  kind: "transcript",
  messages: [],
  inputBar: readyEmptyInputBar,
})
assert.match(inspectorEmptyMarkup, /class="chat-transcript"/)
assert.doesNotMatch(inspectorEmptyMarkup, /class="chat-empty"/)
assert.doesNotMatch(inspectorEmptyMarkup, /Ask Voyager/)
assert.match(inspectorEmptyMarkup, /aria-label="Chat message"/)

const centeredEmptyMarkup = renderChatSurface({
  kind: "centeredEmpty",
  emptyTitle: "Ask Voyager",
  emptyDetail: "Explore your files, collections, and ideas with Voyager.",
  inputBar: readyEmptyInputBar,
})
assert.match(centeredEmptyMarkup, /Ask Voyager/)
assert.match(centeredEmptyMarkup, /Explore your files, collections, and ideas with Voyager\./)
assert.match(centeredEmptyMarkup, /class="chat-empty"/)
assert.match(centeredEmptyMarkup, /class="chat-empty-icon"/)
assert.doesNotMatch(centeredEmptyMarkup, /AI provider status/)

const centeredUnconnectedMarkup = renderChatSurface({
  kind: "centeredEmpty",
  emptyTitle: "Ask Voyager",
  emptyDetail: "Explore your files, collections, and ideas with Voyager.",
  inputBar: readyEmptyInputBar,
  connectionError: {
    title: "Connect an AI provider",
    detail: "Set up a provider in Settings to chat with this context.",
    actionLabel: "Open Settings",
  },
})
assert.match(centeredUnconnectedMarkup, /Ask Voyager/)
assert.match(centeredUnconnectedMarkup, /Connect an AI provider/)
assert.match(centeredUnconnectedMarkup, /class="chat-connection-cta"/)
assert.ok(
  centeredUnconnectedMarkup.indexOf("Ask Voyager") <
    centeredUnconnectedMarkup.indexOf('aria-label="Chat message"'),
)

const connectionErrorMarkup = renderChatSurface({
  kind: "connectionError",
  inputBar: readyEmptyInputBar,
  connectionError: {
    title: "Chat unavailable",
    detail: "The last request failed before completing. Retry to continue.",
    actionLabel: "Retry",
  },
})
assert.match(connectionErrorMarkup, /Chat unavailable/)
assert.match(connectionErrorMarkup, />Retry</)
assert.match(connectionErrorMarkup, /aria-label="AI provider status"/)
assert.ok(
  connectionErrorMarkup.indexOf('aria-label="AI provider status"') <
    connectionErrorMarkup.indexOf('aria-label="Chat message"'),
)

const rebindMarkup = renderChatSurface({
  kind: "transcript",
  messages: [{ id: "m1", role: "user", content: "Summarize the selected research PDFs." }],
  inputBar: readyEmptyInputBar,
  rebindRequired: true,
})
assert.match(rebindMarkup, /Session needs rebind/)
assert.match(rebindMarkup, /Rebind context/)
assert.match(rebindMarkup, /Start new chat/)
assert.match(rebindMarkup, /aria-label="Rebind required"/)
assert.ok(
  rebindMarkup.indexOf('aria-label="Rebind required"') <
    rebindMarkup.indexOf('aria-label="Chat message"'),
)

assert.deepEqual(Object.keys(runtime).sort(), ["FileManagerIllustration"])
assert.deepEqual(Object.keys(packageJson.exports).sort(), [".", "./styles.css"])

const expectedPublicTypes = [
  "FileManagerIllustrationProps",
  "FileEntry",
  "EntryKind",
  "ContentTab",
  "ContentContext",
]
const typeExportBlock = sourceBarrel.match(/export type\s*\{([\s\S]*?)\}\s*from/)
assert.ok(typeExportBlock, "Missing public type export block")
const publicTypes = typeExportBlock[1]
  .split(",")
  .map((typeName) => typeName.trim())
  .filter(Boolean)
assert.deepEqual(publicTypes.sort(), expectedPublicTypes.sort())
assert.match(macosTokens, /--macos-label-color\s*:/)
const fixedColorBlock = macosTokens.match(
  /SWIFTUI-FIXED-COLORS:BEGIN([\s\S]*?)SWIFTUI-FIXED-COLORS:END/,
)
const sequoiaColorBlock = macosTokens.match(
  /SWIFTUI-SYSTEM-COLORS:sequoia:BEGIN([\s\S]*?)SWIFTUI-SYSTEM-COLORS:sequoia:END/,
)
const tahoeColorBlock = macosTokens.match(
  /SWIFTUI-SYSTEM-COLORS:tahoe:BEGIN([\s\S]*?)SWIFTUI-SYSTEM-COLORS:tahoe:END/,
)
assert.ok(fixedColorBlock, "Missing baseline-independent SwiftUI fixed colors")
assert.ok(sequoiaColorBlock, "Missing Sequoia SwiftUI dynamic colors")
assert.ok(tahoeColorBlock, "Missing Tahoe SwiftUI dynamic colors")
assert.match(fixedColorBlock[1], /:root \[data-file-manager-illustration\]/)
assert.match(fixedColorBlock[1], /--swiftui-black:\s*#000000ff/)
assert.match(fixedColorBlock[1], /--swiftui-white:\s*#ffffffff/)
assert.match(fixedColorBlock[1], /--swiftui-clear:\s*#00000000/)
assert.doesNotMatch(sequoiaColorBlock[1], /--swiftui-(?:black|white|clear):/)
assert.doesNotMatch(tahoeColorBlock[1], /--swiftui-(?:black|white|clear):/)
assert.match(macosTokens, /SWIFTUI-SYSTEM-COLORS:sequoia:BEGIN/)
assert.match(macosTokens, /--swiftui-primary:\s*#000000d8/)
assert.match(macosTokens, /data-voyager-color-scheme-contrast="increased"/)
const sequoiaDarkMediaSelector =
  /:root\[data-voyager-visual-baseline="sequoia"\]:not\(\[data-voyager-color-scheme="light"\]\)/
assert.match(macosTokens, sequoiaDarkMediaSelector)
assert.match(fileManagerCss, sequoiaDarkMediaSelector)
assert.match(generatedMaterialMetadata, /Material\.ultraThinMaterial/)
assert.match(generatedMaterialMetadata, /Glass\.regular/)
assert.match(generatedMaterialMetadata, /tahoeRuntimeMeasured:\s*true/)
assert.match(
  generatedMaterialMetadata,
  /rgbaPolicy:\s*"materials-and-glass-are-contextual-shape-styles"/,
)
assert.doesNotMatch(
  designTokensStorySource,
  /globals:\s*\{\s*visualBaseline:\s*swiftUIMaterialMetadata\.sourceBaseline\s*\}/,
)
assert.doesNotMatch(designTokensStorySource, /swiftUIMaterialMetadata\.sourceBaseline/)
assert.doesNotMatch(fileManagerCss, /--macos-[a-z0-9-]+\s*:/)
verifyChatMessageContract(packageRoot, css)
verifyChatInteractionContract(packageRoot)
verifyDesignVersionContract(packageRoot, storybookRoot, css)

for (const contract of [
  "--fm-native-window-width: 960px",
  "--fm-native-window-height: 510px",
  "--fm-native-window-min-width: 600px",
  "--fm-native-window-min-height: 350px",
  "--fm-native-sidebar-min-width: 150px",
  "--fm-native-inspector-min-width: 230px",
  "--fm-native-content-min-width: 400px",
  ".sidebar-titlebar",
  "height: 50px",
  ".toolbar",
  "height: 40px",
  ".statusbar",
  "height: 24px",
]) {
  assert.ok(css.includes(contract), `Missing CSS contract: ${contract}`)
}

assert.doesNotMatch(css, /\.window-chrome\s*\{|\.window-title\s*\{|\.view-icons\s*\{/)

/* ── sessions row 수치 계약 (native displayRow: v8/leading10, spacing2, 13 semibold / caption 12) ── */
assert.match(css, /\.chat-sessions-row\s*\{[^}]*gap: 2px/)
assert.match(css, /\.chat-sessions-row\s*\{[^}]*padding: var\(--fm-space-4\) var\(--fm-space-5\)/)
assert.match(css, /\.chat-sessions-row-title\s*\{[^}]*font-weight: var\(--fm-weight-semibold\)/)
assert.match(css, /\.chat-sessions-row-detail\s*\{[^}]*font-size: var\(--fm-font-size-caption\)/)
assert.match(css, /\.chat-sessions-empty\s*\{[^}]*gap: var\(--fm-space-2\)/)
assert.match(css, /\.chat-sessions-loading\s*\{[^}]*gap: var\(--fm-space-4\)/)
assert.match(css, /\.chat-empty-content\s*\{[^}]*gap: 16px/)
assert.match(css, /\.chat-empty-icon\s*\{[^}]*width: 56px/)
assert.match(css, /\.chat-connection-cta\s*\{[^}]*padding: 12px 14px/)

const entries = Object.values(index.entries ?? {})
const fileManagerStories = entries.filter(
  (entry) => entry.type === "story" && entry.title?.startsWith("File Manager/"),
)
const fileManagerPaths = new Set(fileManagerStories.map((entry) => entry.importPath))
const nonFileManagerStories = entries.filter(
  (entry) => entry.type === "story" && !entry.title?.startsWith("File Manager/"),
)
const designTokensStory = fileManagerStories.find(
  (entry) => entry.id === "file-manager-design-tokens--overview",
)

assert.ok(designTokensStory, "Missing File Manager design tokens overview story")
assert.equal(
  designTokensStory.importPath,
  "./packages/file-manager-illustration/src/Foundations/DesignTokens.stories.tsx",
)
assert.equal(fileManagerStories.length, 245)
assert.equal(fileManagerPaths.size, 51)
assert.equal(nonFileManagerStories.length, 0)
for (const storyName of ["Centered Empty", "Centered Unconnected", "Connection Error", "Rebind"]) {
  assert.ok(
    fileManagerStories.some(
      (entry) =>
        entry.importPath ===
          "./packages/file-manager-illustration/src/Domains/Chat/AiChatView.stories.tsx" &&
        entry.name === storyName,
    ),
    `Missing AiChatView story: ${storyName}`,
  )
}
for (const rootStoryName of ["Chat Connection Error", "Chat Rebind"]) {
  assert.ok(
    fileManagerStories.some(
      (entry) =>
        entry.importPath ===
          "./packages/file-manager-illustration/src/Stories/FileManagerIllustration.stories.tsx" &&
        entry.name === rootStoryName,
    ),
    `Missing root story: ${rootStoryName}`,
  )
}
assert.ok(
  fileManagerStories.some(
    (entry) =>
      entry.importPath ===
        "./packages/file-manager-illustration/src/Domains/Chat/AiChatView.stories.tsx" &&
      entry.name === "Unconnected",
  ),
)
assert.ok(
  fileManagerStories.some(
    (entry) =>
      entry.importPath ===
        "./packages/file-manager-illustration/src/Stories/FileManagerIllustration.stories.tsx" &&
      entry.name === "Chat Unconnected",
  ),
)

/* ── RED→GREEN contract: thumbnailSrc data path + asset verification ── */

const thumbnailFiles = [
  {
    id: "img-1",
    displayName: "Photo.png",
    kind: "image",
    extension: "png",
    secondaryLabel: null,
    thumbnailSrc: "https://example.com/photo.png",
  },
  {
    id: "folder-1",
    displayName: "Folder",
    kind: "folder",
    extension: null,
    secondaryLabel: null,
  },
  {
    id: "pdf-1",
    displayName: "Doc.pdf",
    kind: "pdf",
    extension: "pdf",
    secondaryLabel: null,
  },
  {
    id: "doc-1",
    displayName: "Notes.doc",
    kind: "doc",
    extension: "doc",
    secondaryLabel: null,
  },
]

function renderWithFiles(files) {
  return renderToStaticMarkup(
    createElement(runtime.FileManagerIllustration, {
      files,
      contentContext: { tabs, activeTabId: "directory" },
    }),
  )
}

const thumbnailMarkup = renderWithFiles(thumbnailFiles)
verifyThumbnailFixtures(packageRoot, thumbnailMarkup)

console.log("native layout contract: pass")
console.log(`catalog: ${fileManagerStories.length} stories / ${fileManagerPaths.size} paths`)
console.log(`runtime exports: ${JSON.stringify(Object.keys(runtime).sort())}`)
