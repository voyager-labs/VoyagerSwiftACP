import { TabBar, type TabBarItem } from "@voyager-labs/design-foundation"
import { useState } from "react"
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

/** 상단 탭 항목 정의: 아이콘 + 라벨. 네이티브 SettingsSection.visibleCases와 일치한다. */
const TABS: readonly TabBarItem[] = [
  { id: "general", label: "General", icon: "gear" },
  { id: "appearance", label: "Appearance", icon: "paintbrush" },
  { id: "ai", label: "AI", icon: "sparkle" },
]

/** macOS System Settings TabView idiom을 따르는 Settings 일러스트레이션 루트 컴포넌트. */
export const SettingsWindow: FC<SettingsIllustrationProps> = ({ state }) => {
  // 유일한 상호작용: 상단 탭 전환. 초기값은 fixture의 activeTab에서 시드한다.
  const [activeTab, setActiveTab] = useState<SettingsTab>(state.activeTab)

  return (
    <div data-settings-illustration>
      <main className="stage">
        <section className="mac-window" aria-label="Voyager Settings">
          <div className="mac-titlebar">
            <div className="traffic-lights" aria-hidden="true">
              <span className="traffic-light close" />
              <span className="traffic-light minimize" />
              <span className="traffic-light zoom" />
            </div>
            <span className="titlebar-label">Settings</span>
          </div>
          <TabBar
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
