import type { Meta, StoryObj } from "@storybook/react-vite"
import type { TabItem } from "../../../../packages/design-foundation/src/UI/Navigation/TabView"
import { TabViewItem } from "../../../../packages/design-foundation/src/UI/Navigation/TabViewItem"

/** 제품 비종속 중립 픽스처. 아이콘은 SF Symbol 이름. */
const homeItem: TabItem = { id: "home", label: "Home", icon: "house" }

const meta = {
  component: TabViewItem,
  tags: ["autodocs"],
  parameters: { layout: "fullscreen" },
  // 결정적 표현만을 위한 no-op 핸들러 (상태 전환 없음).
  args: {
    item: homeItem,
    onSelect: () => {},
  },
} satisfies Meta<typeof TabViewItem>

export default meta
type Story = StoryObj<typeof meta>

/** [data-design-foundation] 서피스 위에 light 배경으로 TabViewItem을 중앙 배치한다. */
function TabViewItemSurface({ children }: { children: React.ReactNode }) {
  return (
    <div
      data-design-foundation
      style={{
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        height: "100vh",
        background: "var(--macos-under-page-background-color)",
      }}
    >
      {children}
    </div>
  )
}

/** 기본 — 비활성 상태. 아이콘(위) + 라벨(아래)의 세로 배치. */
export const Default: Story = {
  args: { isActive: false },
  render: (args) => (
    <TabViewItemSurface>
      <TabViewItem {...args} />
    </TabViewItemSurface>
  ),
}

/** 활성 상태 — accent 색 + 하단 underline 인디케이터. */
export const Active: Story = {
  args: { isActive: true },
  render: (args) => (
    <TabViewItemSurface>
      <TabViewItem {...args} />
    </TabViewItemSurface>
  ),
}
