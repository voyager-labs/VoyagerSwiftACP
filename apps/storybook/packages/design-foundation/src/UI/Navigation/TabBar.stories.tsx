import type { Meta, StoryObj } from "@storybook/react-vite"
import { TabBar, type TabBarItem } from "./TabBar"

/** Settings 창의 3개 탭 샘플. 아이콘은 SF Symbol 이름. */
const items: readonly TabBarItem[] = [
  { id: "general", label: "General", icon: "gear" },
  { id: "appearance", label: "Appearance", icon: "paintbrush" },
  { id: "ai", label: "AI", icon: "sparkle" },
] as const

const meta = {
  component: TabBar,
  tags: ["autodocs"],
  parameters: { layout: "fullscreen" },
  // 결정적 표현만을 위한 no-op 핸들러 (상태 전환 없음).
  args: {
    items,
    onSelect: () => {},
    ariaLabel: "Settings categories",
  },
} satisfies Meta<typeof TabBar>

export default meta
type Story = StoryObj<typeof meta>

/** [data-design-foundation] 서피스 위에 light 배경으로 TabBar를 배치한다. */
function TabBarSurface({ children }: { children: React.ReactNode }) {
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

/** 기본 — General 탭 활성. */
export const Default: Story = {
  args: { activeId: "general" },
  render: (args) => (
    <TabBarSurface>
      <TabBar {...args} />
    </TabBarSurface>
  ),
}

/** Appearance 탭 활성. */
export const AppearanceActive: Story = {
  args: { activeId: "appearance" },
  render: (args) => (
    <TabBarSurface>
      <TabBar {...args} />
    </TabBarSurface>
  ),
}

/** AI 탭 활성. */
export const AiActive: Story = {
  args: { activeId: "ai" },
  render: (args) => (
    <TabBarSurface>
      <TabBar {...args} />
    </TabBarSurface>
  ),
}
