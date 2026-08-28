import type { Meta, StoryObj } from "@storybook/react-vite"
import { SettingsWindow } from "../../../packages/settings-illustration/src/SettingsWindow"
import {
  aiConnectedState,
  aiModelSettingsExpandedState,
  aiTabState,
  appearanceCustomizeExpandedState,
  appearanceTabState,
  defaultSettingsState,
} from "../../../packages/settings-illustration/src/data/settings-fixtures"

const meta = {
  component: SettingsWindow,
  tags: ["autodocs"],
  parameters: { layout: "fullscreen" },
} satisfies Meta<typeof SettingsWindow>

export default meta
type Story = StoryObj<typeof meta>

/** 기본(General) 탭 — 모든 AI 공급자 미연결. */
export const Default: Story = {
  args: { state: defaultSettingsState },
}

/** Appearance 탭. */
export const AppearanceTab: Story = {
  args: { state: appearanceTabState },
}

/** AI 탭 — 미연결 공급자. */
export const AiTab: Story = {
  args: { state: aiTabState },
}

/** AI 탭 — 모든 공급자 연결됨. */
export const AiTabConnected: Story = {
  args: { state: aiConnectedState },
}

/** Appearance 탭 — 'Customize per view' disclosure 확장. */
export const AppearanceCustomizeExpanded: Story = {
  args: { state: appearanceCustomizeExpandedState },
}

/** AI 탭 — 두 모델 설정 disclosure 그룹 모두 확장. */
export const AiModelSettingsExpanded: Story = {
  args: { state: aiModelSettingsExpandedState },
}
