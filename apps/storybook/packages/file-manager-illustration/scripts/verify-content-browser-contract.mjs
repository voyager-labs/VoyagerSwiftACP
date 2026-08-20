import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { resolve } from "node:path"
import { createElement } from "react"
import { renderToStaticMarkup } from "react-dom/server"

export function verifyContentBrowserContract(packageRoot, css, runtime, fileManagerStories) {
  const source = (relativePath) => readFileSync(resolve(packageRoot, relativePath), "utf8")

  const typesSource = source("src/model/types.ts")
  const adapterSource = source("src/lib/file-manager-adapter.ts")
  const reducerSource = source("src/model/reducer.ts")
  const fixtureSource = source("src/data/content-browser-fixtures.ts")
  const storySource = source("../../src/FileManager/Stories/ContentBrowserStates.stories.tsx")
  const entryListSource = source("src/Domains/Entries/EntryList.tsx")
  const entryListRowSource = source("src/Domains/Entries/EntryListRow.tsx")
  const toolbarSource = source("src/Patterns/Content/FileToolbar.tsx")
  const toolbarNavigationSource = source("src/Patterns/Content/ToolbarNavigation.tsx")

  assert.match(typesSource, /export type FileManagerInitialPresentation/)
  assert.match(typesSource, /readonly initialPresentation\?: FileManagerInitialPresentation/)
  assert.match(adapterSource, /initialPresentation: props\.initialPresentation/)
  assert.match(adapterSource, /dateModified: f\.dateModified/)
  assert.match(adapterSource, /size: f\.size/)
  assert.match(reducerSource, /selectedEntryIds: params\.initialPresentation\.selectedEntryIds/)
  assert.match(reducerSource, /viewMode: params\.initialPresentation\.viewMode/)
  assert.match(reducerSource, /sidebarOpen: params\.initialPresentation\.sidebarOpen/)
  assert.match(reducerSource, /inspectorOpen: params\.initialPresentation\.inspectorOpen/)

  assert.match(fixtureSource, /export const contentBrowserLongNameFiles/)
  assert.match(fixtureSource, /2026-Research-Archive-With-A-Deliberately-Long-Descriptive-Filename/)

  for (const storyName of [
    "DefaultGrid",
    "GridSelection",
    "ListSelection",
    "EmptyGrid",
    "LongNamesList",
    "NarrowSidebarClosed",
    "InspectorOpenList",
  ]) {
    assert.match(storySource, new RegExp(`export const ${storyName}`))
  }

  assert.match(storySource, /className="content-browser-narrow-review"/)
  assert.match(
    css,
    /\.content-browser-narrow-review\s*{[^}]*width:\s*var\(--fm-native-window-min-width\)/s,
  )
  assert.match(
    css,
    /\.content-browser-narrow-review\s+\[data-file-manager-illustration\]\s+\.stage\s*{[^}]*padding:\s*0/s,
  )
  assert.match(css, /\.entry-name\s*{[^}]*-webkit-line-clamp:\s*2/s)
  assert.match(css, /\.entry-name\s*{[^}]*word-break:\s*break-word/s)
  assert.match(css, /\.entry-list-name-leading\s*{[^}]*text-overflow:\s*ellipsis/s)
  assert.match(css, /\.entry-list-name-trailing\s*{[^}]*flex-shrink:\s*0/s)
  assert.match(entryListSource, /<table className="entry-list"/)
  assert.match(entryListSource, /<th scope="col">/)
  assert.doesNotMatch(entryListSource, /aria-hidden="true"/)
  assert.match(entryListRowSource, /intent: EntrySelectionIntent/)
  assert.match(reducerSource, /selectionAnchorId:/)
  assert.match(reducerSource, /case "range":/)
  assert.match(
    toolbarSource,
    /aria-label=\{`Switch to \$\{viewMode === "grid" \? "list" : "grid"\} view`\}/,
  )
  assert.match(toolbarSource, /aria-label="Sort and group" disabled/)
  assert.match(toolbarNavigationSource, /disabled/)

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
      dateModified: "Aug 12, 10:42 AM",
      size: "1.2 MB",
    },
  ]
  const render = (initialPresentation) =>
    renderToStaticMarkup(
      createElement(runtime.FileManagerIllustration, {
        files,
        contentContext: { tabs, activeTabId: "directory" },
        initialPresentation,
      }),
    )

  const listSelectionMarkup = render({
    selectedEntryIds: ["entry-1"],
    viewMode: "list",
    sidebarOpen: true,
    inspectorOpen: false,
  })
  assert.match(listSelectionMarkup, /class="entry-list"/)
  assert.match(listSelectionMarkup, /aria-selected="true"/)
  assert.match(listSelectionMarkup, /<table class="entry-list"/)
  assert.match(listSelectionMarkup, /<th scope="col">/)
  assert.match(listSelectionMarkup, /Aug 12, 10:42 AM/)
  assert.match(listSelectionMarkup, /1\.2 MB/)
  assert.match(listSelectionMarkup, /1 of 1 selected/)

  const narrowSidebarClosedMarkup = render({
    selectedEntryIds: [],
    viewMode: "grid",
    sidebarOpen: false,
    inspectorOpen: false,
  })
  assert.match(narrowSidebarClosedMarkup, /class="mac-window inspector-closed sidebar-closed"/)
  assert.doesNotMatch(narrowSidebarClosedMarkup, /aria-label="Sidebar"/)
  assert.match(narrowSidebarClosedMarkup, /aria-label="Show Sidebar"/)

  const inspectorOpenMarkup = render({
    selectedEntryIds: [],
    viewMode: "grid",
    sidebarOpen: true,
    inspectorOpen: true,
  })
  assert.match(inspectorOpenMarkup, /id="fm-inspector-pane"/)

  const storyIDs = [
    "file-manager-stories-contentbrowserstates--default-grid",
    "file-manager-stories-contentbrowserstates--grid-selection",
    "file-manager-stories-contentbrowserstates--list-selection",
    "file-manager-stories-contentbrowserstates--empty-grid",
    "file-manager-stories-contentbrowserstates--long-names-list",
    "file-manager-stories-contentbrowserstates--narrow-sidebar-closed",
    "file-manager-stories-contentbrowserstates--inspector-open-list",
  ]
  for (const storyID of storyIDs) {
    const story = fileManagerStories.find((entry) => entry.id === storyID)
    assert.ok(story, `Missing VOY-720 content browser story: ${storyID}`)
    assert.equal(story.importPath, "./src/FileManager/Stories/ContentBrowserStates.stories.tsx")
  }
}
