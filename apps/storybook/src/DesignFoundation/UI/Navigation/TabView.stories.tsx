import type { Meta, StoryObj } from "@storybook/react-vite"
import {
  type TabItem,
  TabView,
} from "../../../../packages/design-foundation/src/UI/Navigation/TabView"

/** 제품 비종속 중립 픽스처. 아이콘은 SF Symbol 이름. */
const items: readonly TabItem[] = [
  { id: "home", label: "Home", icon: "house" },
  { id: "library", label: "Library", icon: "books.vertical" },
  { id: "profile", label: "Profile", icon: "person.crop.circle" },
] as const

const meta = {
  component: TabView,
  tags: ["autodocs"],
  parameters: { layout: "fullscreen" },
  // 결정적 표현만을 위한 no-op 핸들러 (상태 전환 없음).
  args: {
    items,
    onSelect: () => {},
    ariaLabel: "Navigation",
  },
} satisfies Meta<typeof TabView>

export default meta
type Story = StoryObj<typeof meta>

/** [data-design-foundation] 서피스 위에 light 배경으로 TabView를 중앙 배치한다. */
function TabViewSurface({ children }: { children: React.ReactNode }) {
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

/** 기본 — Home 항목 활성. */
export const Default: Story = {
  args: { activeId: "home" },
  render: (args) => (
    <TabViewSurface>
      <TabView {...args} />
    </TabViewSurface>
  ),
}

/** Library 항목 활성. */
export const LibraryActive: Story = {
  args: { activeId: "library" },
  render: (args) => (
    <TabViewSurface>
      <TabView {...args} />
    </TabViewSurface>
  ),
}

/** Profile 항목 활성. */
export const ProfileActive: Story = {
  args: { activeId: "profile" },
  render: (args) => (
    <TabViewSurface>
      <TabView {...args} />
    </TabViewSurface>
  ),
}
