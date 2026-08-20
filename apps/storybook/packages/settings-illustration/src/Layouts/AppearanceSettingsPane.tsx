import { SegmentedControl, Toggle } from "@voyager-labs/design-foundation"
import type { FC } from "react"
import "../styles/appearance-pane.css"

type AppearanceTheme = "auto" | "light" | "dark"

interface AppearanceSettingsPaneProps {
  /** true이면 "Customize per view" disclosure가 펼쳐진 상태로 렌더링된다. 기본은 닫힘. */
  readonly customizeOpen?: boolean
}

/** 테마 카드 3종 (Auto/Light/Dark). 네이티브는 .system으로 Auto에 대응한다. */
const THEMES: readonly { id: AppearanceTheme; label: string }[] = [
  { id: "auto", label: "Auto" },
  { id: "light", label: "Light" },
  { id: "dark", label: "Dark" },
]

/** View size 세그먼트 옵션. 네이티브 SizePreset(small/medium/large)에 대응한다. */
const SIZES = ["Small", "Medium", "Large"] as const

/** foundation SegmentedControl용 옵션 (value === label). */
const SIZE_OPTIONS = SIZES.map((size) => ({ value: size, label: size }))

/** Appearance 탭 pane: macOS 네이티브 AppearanceSettingsView의 결정적(비상호작용) 일러스트레이션. */
export const AppearanceSettingsPane: FC<AppearanceSettingsPaneProps> = ({
  customizeOpen = false,
}) => {
  return (
    <div className="settings-form appearance-pane">
      {/* Theme 섹션: 100px 라벨 + 테마 카드 3개. 네이티브 .frame(width:100) (AppearanceSettingsView.swift:235) */}
      <section className="settings-section">
        <div className="settings-row theme-row">
          <span className="settings-row-label">Theme</span>
          <fieldset className="theme-card-list" aria-label="Theme">
            {THEMES.map((theme) => (
              <ThemeCard key={theme.id} theme={theme} isSelected={theme.id === "auto"} />
            ))}
          </fieldset>
        </div>
      </section>

      {/* File display 섹션: Show Hidden Files 토글 (끔) */}
      <section className="settings-section">
        <h2 className="settings-section-header">File display</h2>
        <div className="settings-row">
          <span className="settings-row-label">Show Hidden Files</span>
          {/* 결정적 표현을 위한 no-op — 일러스트레이션은 상호작용하지 않는다 */}
          <Toggle checked={false} onChange={() => {}} />
        </div>
      </section>

      {/* View size 섹션: Overall + Customize per view disclosure */}
      <section className="settings-section">
        <h2 className="settings-section-header">View size</h2>

        <div className="settings-row">
          <span className="settings-row-label">Overall</span>
          {/* 결정적 표현을 위한 no-op — 일러스트레이션은 상호작용하지 않는다 */}
          <SegmentedControl options={SIZE_OPTIONS} value="Medium" onChange={() => {}} />
        </div>

        <div className={`disclosure-row${customizeOpen ? " is-open" : ""}`}>
          <span className="disclosure-title">Customize per view</span>
          <span className="disclosure-chevron" aria-hidden="true">
            ›
          </span>
        </div>

        {customizeOpen && (
          <div className="disclosure-body">
            <div className="settings-row">
              <span className="settings-row-label">List</span>
              <SegmentedControl options={SIZE_OPTIONS} value="Medium" onChange={() => {}} />
            </div>
            <div className="settings-row">
              <span className="settings-row-label">Icon</span>
              <SegmentedControl options={SIZE_OPTIONS} value="Medium" onChange={() => {}} />
            </div>
          </div>
        )}
      </section>
    </div>
  )
}

AppearanceSettingsPane.displayName = "AppearanceSettingsPane"

/** 테마 미리보기 카드: 80px 폭, 70x42 미리보기 표면 + 라벨. */
function ThemeCard({
  theme,
  isSelected,
}: {
  theme: (typeof THEMES)[number]
  isSelected: boolean
}) {
  return (
    <div className={`theme-card${isSelected ? " is-selected" : ""}`}>
      <div className={`theme-preview is-${theme.id}`} aria-hidden="true">
        {theme.id === "auto" && (
          <span className="theme-popup">
            <span className="traffic-dot is-red" />
            <span className="traffic-dot is-yellow" />
            <span className="traffic-dot is-green" />
          </span>
        )}
      </div>
      <span className={`theme-caption${isSelected ? " is-selected" : ""}`}>{theme.label}</span>
    </div>
  )
}
