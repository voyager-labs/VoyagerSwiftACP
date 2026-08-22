import type { Meta, StoryObj } from "@storybook/react-vite"
import type { FC } from "react"
import { symbols as SF_SYMBOLS } from "symbolist"
import { SFSymbol } from "../../../packages/file-manager-illustration/src/Foundations/SFSymbol"

const meta = {
  component: SFSymbol,
  id: "file-manager-sf-symbols",
  tags: ["autodocs"],
  title: "Foundations/SF Symbols",
  parameters: {
    layout: "fullscreen",
  },
} satisfies Meta<typeof SFSymbol>

export default meta
type Story = StoryObj<typeof meta>

/** 전체 SF Symbol 카탈로그 */
const SymbolGrid: FC<{ size: number }> = ({ size }) => {
  const names = Object.keys(SF_SYMBOLS).sort()
  return (
    <div
      data-file-manager-illustration
      style={{
        display: "grid",
        gridTemplateColumns: `repeat(auto-fill, minmax(${size * 2.5}px, 1fr))`,
        gap: "8px",
        padding: "24px",
        background: "var(--fm-canvas)",
        color: "var(--fm-text-primary)",
      }}
    >
      {names.map((name) => (
        <div
          key={name}
          style={{
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            gap: "4px",
            padding: "12px 8px",
            borderRadius: "8px",
            background: "var(--fm-window)",
            border: "1px solid var(--fm-separator)",
          }}
        >
          <SFSymbol name={name} size={size} />
          <span
            style={{
              fontSize: "10px",
              fontFamily: "var(--fm-font-ui)",
              color: "var(--fm-text-secondary)",
              textAlign: "center",
              wordBreak: "break-all",
              lineHeight: 1.3,
            }}
          >
            {name}
          </span>
        </div>
      ))}
    </div>
  )
}

export const Catalog: Story = {
  args: { name: "folder" },
  render: () => <SymbolGrid size={24} />,
}

export const LargeIcons: Story = {
  args: { name: "folder" },
  render: () => <SymbolGrid size={48} />,
}

export const Single: Story = {
  args: {
    name: "folder",
    size: 32,
    weight: 400,
  },
  render: (args) => (
    <div
      data-file-manager-illustration
      style={{
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        height: "100vh",
        background: "var(--fm-canvas)",
      }}
    >
      <SFSymbol
        name={args.name as string}
        size={args.size as number}
        weight={args.weight as number}
      />
    </div>
  ),
}
