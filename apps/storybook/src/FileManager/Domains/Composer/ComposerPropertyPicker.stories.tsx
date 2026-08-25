import type { Meta, StoryObj } from "@storybook/react-vite"
import { expect, userEvent, within } from "storybook/test"
import { ComposerPropertyPicker } from "../../../../packages/file-manager-illustration/src/Domains/Composer/ComposerPropertyPicker"
import { composerPropertyOptions } from "../../../../packages/file-manager-illustration/src/Domains/Composer/composer-condition-options"

const meta = {
  component: ComposerPropertyPicker,
  tags: ["autodocs"],
  decorators: [
    (Story) => (
      <div className="collection-composer-specimen picker">
        <div className="collection-composer-property-stage">
          <Story />
        </div>
      </div>
    ),
  ],
  args: {
    picker: {
      kind: "property",
      items: composerPropertyOptions,
    },
  },
} satisfies Meta<typeof ComposerPropertyPicker>

export default meta
type Story = StoryObj<typeof meta>

export const Root: Story = {}

export const CategorySubmenu: Story = {
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await userEvent.click(canvas.getByRole("menuitem", { name: "Common" }))
    await expect(canvas.getByRole("menuitem", { name: "Common" })).toHaveAttribute(
      "aria-expanded",
      "true",
    )
    // 루트 메뉴는 유지된 채 인접 서브메뉴가 열린다
    await expect(
      canvas.getByRole("menu", { name: "Condition property picker" }),
    ).toBeInTheDocument()
    const submenu = within(canvas.getByRole("menu", { name: "Common properties" }))
    await expect(submenu.getByRole("menuitem", { name: "Number of pages" })).toBeInTheDocument()
    await expect(submenu.getByRole("menuitem", { name: "Keywords" })).toBeInTheDocument()
    await expect(submenu.getByRole("menuitem", { name: "Kind" })).toBeInTheDocument()
  },
}

export const NoResults: Story = {
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await userEvent.type(canvas.getByRole("searchbox", { name: "Search attributes" }), "zzz")
    // 네이티브 빈 결과: magnifyingglass 이미지를 가진 비활성 행 하나만 남는다
    const items = canvas.getAllByRole("menuitem")
    await expect(items).toHaveLength(1)
    const noResults = canvas.getByRole("menuitem", { name: "No properties found" })
    await expect(noResults).toBeDisabled()
    await expect(noResults.querySelector(".sf-symbol")).not.toBeNull()
  },
}
