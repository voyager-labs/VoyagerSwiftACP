import type { Meta, StoryObj } from "@storybook/react-vite"
import type { FC } from "react"
import { SFSymbol } from "./SFSymbol"

const meta = {
  component: SFSymbol,
  tags: ["autodocs"],
  parameters: { layout: "fullscreen" },
} satisfies Meta<typeof SFSymbol>

export default meta
type Story = StoryObj<typeof meta>

/** [data-design-foundation] 서피스 위에 light 배경 + primary 텍스트 색으로 심볼을 배치한다. */
function SymbolSurface({ children }: { children: React.ReactNode }) {
  return (
    <div
      data-design-foundation
      style={{
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        height: "100vh",
        background: "var(--macos-under-page-background-color)",
        color: "var(--macos-label-color)",
      }}
    >
      {children}
    </div>
  )
}

/** Foundation 탭에서 쓰는 심볼 카탈로그 그리드. */
const SettingsSymbolGrid: FC = () => {
  const names = ["gear", "paintbrush", "sparkle"]
  return (
    <div
      style={{
        display: "grid",
        gridTemplateColumns: "repeat(3, auto)",
        gap: "24px",
        padding: "24px",
        background: "var(--macos-window-background-color)",
        border: "1px solid var(--macos-separator-color)",
        borderRadius: "10px",
      }}
    >
      {names.map((name) => (
        <div
          key={name}
          style={{
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            gap: "8px",
          }}
        >
          <SFSymbol name={name} size={32} weight={500} />
          <span
            style={{
              fontSize: "12px",
              fontFamily:
                '"Voyager SF Pro Text", "Voyager SF Pro Display", -apple-system, sans-serif',
              color: "var(--macos-secondary-label-color)",
            }}
          >
            {name}
          </span>
        </div>
      ))}
    </div>
  )
}

/** Settings General 탭 아이콘. */
export const Gear: Story = {
  args: { name: "gear", size: 32, weight: 500 },
  render: (args) => (
    <SymbolSurface>
      <SFSymbol name={args.name} size={args.size} weight={args.weight} />
    </SymbolSurface>
  ),
}

/** Settings Appearance 탭 아이콘. */
export const Paintbrush: Story = {
  args: { name: "paintbrush", size: 32, weight: 500 },
  render: (args) => (
    <SymbolSurface>
      <SFSymbol name={args.name} size={args.size} weight={args.weight} />
    </SymbolSurface>
  ),
}

/** Settings AI 탭 아이콘. */
export const Sparkle: Story = {
  args: { name: "sparkle", size: 32, weight: 500 },
  render: (args) => (
    <SymbolSurface>
      <SFSymbol name={args.name} size={args.size} weight={args.weight} />
    </SymbolSurface>
  ),
}

/** Settings 탭 심볼 카탈로그. */
export const Catalog: Story = {
  args: { name: "gear" },
  render: () => (
    <SymbolSurface>
      <SettingsSymbolGrid />
    </SymbolSurface>
  ),
}
