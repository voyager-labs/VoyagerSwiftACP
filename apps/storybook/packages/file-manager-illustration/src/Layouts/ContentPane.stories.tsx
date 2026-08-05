import type { Meta, StoryObj } from "@storybook/react-vite"
import { FileToolbar } from "../Patterns/FileToolbar"
import { StatusBar } from "../Patterns/StatusBar"
import { files, noSelection } from "../data/mock-data"
import { directoryBreadcrumb } from "../lib/navigation-data"
import { FileManagerPrimaryContent } from "./FileManagerPrimaryContent"

const contentPaneFiles = files.slice(0, 12)

const meta = {
  component: FileManagerPrimaryContent,
  tags: ["autodocs"],
  parameters: { layout: "fullscreen" },
} satisfies Meta<typeof FileManagerPrimaryContent>

export default meta
type Story = StoryObj<typeof meta>

export const ContentPane: Story = {
  args: {
    route: { kind: "browser" },
    entries: contentPaneFiles,
    selectedEntryIds: noSelection,
    viewMode: "grid",
    onToggleEntry: () => undefined,
    onFavoriteSelect: () => undefined,
    onLocationSelect: () => undefined,
  },
  render: (args) => (
    <div data-file-manager-illustration>
      <main className="stage">
        <section className="content-pane-review" aria-label="Content Pane">
          <FileToolbar
            title="Directory"
            content="directory"
            viewMode="grid"
            showSidebarButton
            onViewModeChange={() => undefined}
            onToggleSidebar={() => undefined}
          />
          <FileManagerPrimaryContent {...args} />
          <StatusBar
            selectedLabel={`${contentPaneFiles.length} items`}
            breadcrumb={directoryBreadcrumb}
          />
        </section>
      </main>
    </div>
  ),
}
