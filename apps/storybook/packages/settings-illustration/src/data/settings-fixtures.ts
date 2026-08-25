import type { AiSettingsModel, SettingsState } from "../model/types"

/** 연결되지 않은 기본 AI 공급자 목록. */
const notConnectedAi: AiSettingsModel = {
  providers: [
    { id: "chatgpt-codex", name: "ChatGPT Codex", authKind: "oauth", status: "notConnected" },
    { id: "openai", name: "OpenAI", authKind: "apiKey", status: "notConnected" },
    { id: "anthropic", name: "Anthropic", authKind: "apiKey", status: "notConnected" },
  ],
  defaultChatSummary: "Not configured",
  collectionSearchSummary: "Automatic · Last-used provider first · First compatible model",
}

/** 기본(General 탭) 설정 상태 — 모든 AI 공급자가 미연결. */
export const defaultSettingsState: SettingsState = {
  activeTab: "general",
  ai: notConnectedAi,
}

/** Appearance 탭 상태 — 동일한 미연결 AI 모델. */
export const appearanceTabState: SettingsState = {
  activeTab: "appearance",
  ai: notConnectedAi,
}

/** AI 탭 상태 — 동일한 미연결 AI 모델. */
export const aiTabState: SettingsState = {
  activeTab: "ai",
  ai: notConnectedAi,
}

/** AI 탭에서 모든 공급자가 연결된 상태. */
export const aiConnectedState: SettingsState = {
  activeTab: "ai",
  ai: {
    providers: [
      {
        id: "chatgpt-codex",
        name: "ChatGPT Codex",
        authKind: "oauth",
        status: "connected",
        account: "crew@voyager.fm",
        expires: "Oct 12, 2026 at 9:41 AM",
      },
      { id: "openai", name: "OpenAI", authKind: "apiKey", status: "connected" },
      { id: "anthropic", name: "Anthropic", authKind: "apiKey", status: "connected" },
    ],
    defaultChatSummary: "ChatGPT Codex · gpt-5.4 · medium",
    collectionSearchSummary: "Automatic · Last-used provider first · First compatible model",
  },
}

/** Appearance 탭에서 'Customize per view' disclosure가 열린 상태. */
export const appearanceCustomizeExpandedState: SettingsState = {
  activeTab: "appearance",
  customizePerViewOpen: true,
  ai: notConnectedAi,
}

/** AI 탭에서 두 모델 설정 disclosure 그룹이 모두 열린 상태. */
export const aiModelSettingsExpandedState: SettingsState = {
  activeTab: "ai",
  defaultChatOpen: true,
  collectionSearchOpen: true,
  ai: notConnectedAi,
}
