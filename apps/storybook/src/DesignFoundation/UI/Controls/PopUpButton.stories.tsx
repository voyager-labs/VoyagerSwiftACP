import type { Meta, StoryObj } from "@storybook/react-vite"
import { PopUpButton } from "../../../../packages/design-foundation/src/UI/Controls/PopUpButton"

const fn = (): (() => void) => () => {}

const fruitOptions = [
  { value: "apple", label: "Apple" },
  { value: "banana", label: "Banana" },
  { value: "cherry", label: "Cherry" },
  { value: "durian", label: "Durian" },
] as const

const meta = {
  component: PopUpButton,
  tags: ["autodocs"],
  args: {
    options: fruitOptions,
    value: "apple",
    onChange: fn(),
  },
} satisfies Meta<typeof PopUpButton>

export default meta
type Story = StoryObj<typeof meta>

export const Default: Story = {}

export const NoSelection: Story = {
  args: { value: undefined, placeholder: "Choose a fruit" },
}

export const WithDetail: Story = {
  args: {
    options: [
      { value: "1", label: "Ascending", detail: "A → Z" },
      { value: "2", label: "Descending", detail: "Z → A" },
      { value: "3", label: "Date modified", detail: "Newest first" },
    ],
    value: "3",
  },
}

export const DisabledOption: Story = {
  args: {
    options: [
      { value: "a", label: "Available" },
      { value: "b", label: "Unavailable", disabled: true },
      { value: "c", label: "Also available" },
    ],
    value: "a",
  },
}

export const Disabled: Story = {
  args: { disabled: true },
}

export const ManyOptions: Story = {
  args: {
    options: Array.from({ length: 20 }, (_, i) => ({
      value: `opt-${i}`,
      label: `Option ${i + 1}`,
    })),
    value: "opt-0",
  },
}
