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
          <button
            type="button"
            className="toggle"
            role="switch"
            aria-checked="false"
            aria-label="Show Hidden Files"
          />
        </div>
      </section>

      {/* View size 섹션: Overall + Customize per view disclosure */}
      <section className="settings-section">
        <h2 className="settings-section-header">View size</h2>

        <div className="settings-row">
          <span className="settings-row-label">Overall</span>
          <Segmented active="Medium" label="Overall" />
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
              <Segmented active="Medium" label="List" />
            </div>
            <div className="settings-row">
              <span className="settings-row-label">Icon</span>
              <Segmented active="Medium" label="Icon" />
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

/** 분할 세그먼트 컨트롤. 공유 .segmented 프리미티브를 사용, Medium이 활성이다. */
function Segmented({ active, label }: { active: string; label: string }) {
  return (
    <fieldset className="segmented" aria-label={label}>
      {SIZES.map((size) => (
        <button key={size} type="button" className={size === active ? "is-active" : undefined}>
          {size}
        </button>
      ))}
    </fieldset>
  )
}
