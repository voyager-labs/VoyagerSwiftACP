import type { Meta, StoryObj } from "@storybook/react-vite"
import { FileManagerPrimaryContent } from "../../../packages/file-manager-illustration/src/Layouts/FileManagerPrimaryContent"
import { FileToolbar } from "../../../packages/file-manager-illustration/src/Patterns/Content/FileToolbar"
import { StatusBar } from "../../../packages/file-manager-illustration/src/Patterns/Content/StatusBar"
import { files, noSelection } from "../../../packages/file-manager-illustration/src/data/mock-data"
import { directoryBreadcrumb } from "../../../packages/file-manager-illustration/src/lib/navigation-data"

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
            viewMode={args.viewMode}
            showSidebarButton
            onViewModeChange={() => undefined}
            onToggleSidebar={() => undefined}
            onNewChat={() => undefined}
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

export const ListView: Story = {
  ...ContentPane,
  args: {
    ...ContentPane.args,
    viewMode: "list",
  },
}
