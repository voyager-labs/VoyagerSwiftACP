import { type TabItem, TabView, TrafficLights } from "@voyager-labs/design-foundation"
import { useEffect, useState } from "react"
import type { FC } from "react"
import { AiSettingsPane } from "./Layouts/AiSettingsPane"
import { AppearanceSettingsPane } from "./Layouts/AppearanceSettingsPane"
import { GeneralSettingsPane } from "./Layouts/GeneralSettingsPane"
import type { SettingsIllustrationProps, SettingsTab } from "./model/types"
import "@voyager-labs/design-foundation/tokens.css"
import "./styles/settings.css"
import "./styles/general-pane.css"
import "./styles/appearance-pane.css"
import "./styles/ai-pane.css"

/** 가로 탭 바 항목 정의: 아이콘 + 라벨. 네이티브 SettingsSection.visibleCases와 일치한다. */
const TABS: readonly TabItem[] = [
  { id: "general", label: "General", icon: "gear" },
  { id: "appearance", label: "Appearance", icon: "paintbrush" },
  { id: "ai", label: "AI", icon: "sparkle" },
]

/** macOS System Settings 가로 탭 바 idiom을 따르는 Settings 일러스트레이션 루트 컴포넌트. */
export const SettingsWindow: FC<SettingsIllustrationProps> = ({ state }) => {
  // 유일한 상호작용: 가로 탭 바 전환. 초기값은 fixture의 activeTab에서 시드한다.
  const [activeTab, setActiveTab] = useState<SettingsTab>(state.activeTab)
  // Storybook Controls에서 fixture의 activeTab이 바뀌면 로컬 탭도 동기화한다.
  useEffect(() => {
    setActiveTab(state.activeTab)
  }, [state.activeTab])

  return (
    <div data-settings-illustration>
      <main className="stage">
        <section className="mac-window" aria-label="Voyager Settings">
          {/* 얇은 타이틀바: 트래픽 라이트 + 창 제목. 구분선 없이 탭바로 이어진다. */}
          <div className="mac-titlebar">
            <TrafficLights />
            <span className="mac-titlebar-label">Settings</span>
          </div>
          <TabView
            items={TABS}
            activeId={activeTab}
            onSelect={(id) => setActiveTab(id as SettingsTab)}
            ariaLabel="Settings categories"
          />
          <div className="settings-pane">
            {activeTab === "general" ? (
              <GeneralSettingsPane />
            ) : activeTab === "appearance" ? (
              <AppearanceSettingsPane customizeOpen={state.customizePerViewOpen} />
            ) : (
              <AiSettingsPane
                model={state.ai}
                defaultChatOpen={state.defaultChatOpen}
                collectionSearchOpen={state.collectionSearchOpen}
              />
            )}
          </div>
        </section>
      </main>
    </div>
  )
}

SettingsWindow.displayName = "SettingsWindow"
