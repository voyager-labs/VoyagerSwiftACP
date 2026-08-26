/** Settings 창의 상단 탭 식별자. */
export type SettingsTab = "general" | "appearance" | "ai"

/** AI 연결 공급자 행. */
export interface AiProviderRow {
  readonly id: string
  readonly name: string
  readonly authKind: "oauth" | "apiKey"
  readonly status: "notConnected" | "connected"
  readonly account?: string
  readonly expires?: string
}

/** AI 모델 설정 상태. */
export interface AiSettingsModel {
  readonly providers: readonly AiProviderRow[]
  readonly defaultChatSummary: string
  readonly collectionSearchSummary: string
}

/** Settings 일러스트레이션의 결정적(fixture 기반) 상태. */
export interface SettingsState {
  readonly activeTab: SettingsTab
  readonly ai: AiSettingsModel
  // 선택적 프레젠테이션 플래그 (확장된 disclosure 상태 — 기본은 닫힘)
  readonly customizePerViewOpen?: boolean
  readonly defaultChatOpen?: boolean
  readonly collectionSearchOpen?: boolean
}

/** 공개 루트 props — 프레젠테이션 일러스트레이션이며 live reducer가 아니다. */
export interface SettingsIllustrationProps {
  readonly state: SettingsState
}
