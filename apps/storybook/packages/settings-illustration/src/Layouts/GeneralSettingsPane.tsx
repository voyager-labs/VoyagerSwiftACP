import { Toggle } from "@voyager-labs/design-foundation"
import type { FC } from "react"
import "../styles/general-pane.css"

/**
 * General 설정 pane (네이티브 GeneralSettingsView의 결정적 기본 상태).
 *
 * 프레젠테이션 일러스트레이션이므로 props를 받지 않으며, 토글/버튼/메뉴는
 * 상호작용하지 않는 고정 상태로 렌더링한다. 행 순서와 문자열은 네이티브
 * GeneralSettingsView.swift와 정확히 일치한다.
 */
export const GeneralSettingsPane: FC = () => {
  return (
    <div className="settings-form">
      <section className="settings-section">
        <div className="settings-row">
          <span className="settings-row-label">Launch at startup</span>
          {/* 결정적 표현을 위한 no-op — 일러스트레이션은 상호작용하지 않는다 */}
          <Toggle checked onChange={() => {}} />
        </div>
        <div className="settings-row">
          <span className="settings-row-label">Alert before app quit</span>
          {/* 결정적 표현을 위한 no-op — 일러스트레이션은 상호작용하지 않는다 */}
          <Toggle checked onChange={() => {}} />
        </div>
      </section>

      <section className="settings-section">
        <h2 className="settings-section-header">Updates</h2>
        <div className="settings-row">
          <span className="settings-row-label">Automatically download and install updates</span>
          {/* 결정적 표현을 위한 no-op — 일러스트레이션은 상호작용하지 않는다 */}
          <Toggle checked onChange={() => {}} />
        </div>
        <div className="settings-divider" aria-hidden="true" />
        <div className="settings-row">
          <span className="settings-row-label">Version: 1.0.0</span>
          <span className="settings-button">Check for updates...</span>
        </div>
      </section>

      <section className="settings-section">
        <h2 className="settings-section-header">Workspace</h2>
        <div className="settings-row">
          <span className="settings-row-label">Starting directory</span>
          <span className="settings-menu-button">Home (default)</span>
        </div>
      </section>

      <section className="settings-section">
        <h2 className="settings-section-header">Default File Viewer</h2>
        <div className="settings-row">
          <span className="settings-row-label">
            Could not determine the default file viewer status.
          </span>
          <span className="settings-button">Check Again</span>
        </div>
        <p className="footnote settings-footnote">
          A system restart may be required for changes to take effect.
        </p>
      </section>
    </div>
  )
}

GeneralSettingsPane.displayName = "GeneralSettingsPane"
