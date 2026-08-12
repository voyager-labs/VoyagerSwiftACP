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

const directoryMarkup = render("directory")
const homeMarkup = render("home")

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
assert.equal(fileManagerStories.length, 192)
assert.equal(fileManagerPaths.size, 43)
assert.equal(nonFileManagerStories.length, 0)

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
