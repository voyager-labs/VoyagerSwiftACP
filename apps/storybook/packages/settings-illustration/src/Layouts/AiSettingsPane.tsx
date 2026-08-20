import { Button, PopUpButton, TextField } from "@voyager-labs/design-foundation"
import type { FC } from "react"
import type { AiProviderRow, AiSettingsModel } from "../model/types"
import "../styles/ai-pane.css"

/**
 * AI 설정 pane (네이티브 AiSettingsView의 결정적 기본 상태).
 *
 * 프레젠테이션 일러스트레이션이므로 실제 인증/네트워크 동작 없이 model prop에서
 * 렌더링만 수행한다. picker는 상호작용하지 않는 고정 라벨이며, 패스워드 입력과
 * Submit 버튼은 빈 정적 입력/비활성 상태로만 표시한다. 섹션·문자열은 네이티브
 * AiSettingsView.swift와 정확히 일치한다.
 */
export interface AiSettingsPaneProps {
  readonly model: AiSettingsModel
  readonly defaultChatOpen?: boolean
  readonly collectionSearchOpen?: boolean
}

const DEFAULT_CHAT_FOOTER =
  "Applies only to new conversations. Existing conversations and Collection Search are not affected."
const COLLECTION_SEARCH_FOOTER =
  "These preferences are stored locally and used by collection search only."
const COLLECTION_SEARCH_AUTO_EXPLANATION =
  "Auto uses the last-used available provider first and the first compatible model at runtime."

/** 상태 배지에 표시할 점 + 캡션. */
function ConnectionStatus({ status }: { status: AiProviderRow["status"] }) {
  const connected = status === "connected"
  return (
    <span className="ai-status">
      <span
        className={connected ? "status-dot is-connected" : "status-dot is-not-connected"}
        aria-hidden="true"
      />
      <span className="ai-status-caption">{connected ? "Connected" : "Not connected"}</span>
    </span>
  )
}

/** 행 우측 트레일링 액션 (인증 방식/상태에 따라 결정). */
function ConnectionAction({ provider }: { provider: AiProviderRow }) {
  if (provider.status === "notConnected") {
    if (provider.authKind === "oauth") {
      return <Button>Sign in</Button>
    }
    return (
      <span className="ai-action">
        {/* 결정적 표현을 위한 정적 입력 — 일러스트레이션은 상호작용하지 않는다 */}
        <TextField placeholder="Enter API key" readOnly className="ai-password-input" />
        <Button disabled>Submit</Button>
      </span>
    )
  }

  return (
    <span className="ai-action ai-action-connected">
      <span className="ai-account-lines">
        {provider.account ? <span>Account: {provider.account}</span> : null}
        {provider.expires ? <span>Expires: {provider.expires}</span> : null}
      </span>
      <Button>Disconnect</Button>
    </span>
  )
}

/** AI Model Settings 섹션의 단일 설정 행 (라벨 좌 / picker 우). */
function ModelSettingRow({
  label,
  value,
  disabled = false,
}: { label: string; value: string; disabled?: boolean }) {
  return (
    <div className="settings-row ai-model-row">
      <span className="settings-row-label">{label}</span>
      {/* 결정적 표현을 위한 no-op — 일러스트레이션은 상호작용하지 않는다 */}
      <PopUpButton
        className="ai-picker-label"
        options={[{ value, label: value }]}
        value={value}
        disabled={disabled}
        onChange={() => {}}
      />
    </div>
  )
}

/** Default Chat / Collection Search disclosure 본문. */
function ModelSettingsEditor({
  provider,
  model,
  thinking,
  resetLabel,
  footnotes,
}: {
  provider: string
  model: string
  thinking: string
  resetLabel: string
  footnotes: string[]
}) {
  return (
    <div className="ai-editor">
      <ModelSettingRow label="Provider" value={provider} />
      <ModelSettingRow label="Model" value={model} disabled />
      <ModelSettingRow label="Thinking" value={thinking} />
      <div className="ai-editor-footer">
        <Button className="ai-button-reset">{resetLabel}</Button>
      </div>
      <div className="ai-editor-footnotes">
        {footnotes.map((note) => (
          <p key={note} className="footnote">
            {note}
          </p>
        ))}
      </div>
    </div>
  )
}

/** Disclosure 행 (제목 + 요약 + chevron). */
function DisclosureRow({
  title,
  summary,
  open,
  children,
}: {
  title: string
  summary: string
  open: boolean
  children: React.ReactNode
}) {
  return (
    <div className={open ? "disclosure-row is-open" : "disclosure-row"}>
      <span className="disclosure-copy">
        <span className="disclosure-title">{title}</span>
        <span className="disclosure-summary">{summary}</span>
      </span>
      <span className="disclosure-chevron" aria-hidden="true">
        ›
      </span>
      {open ? <div className="disclosure-body">{children}</div> : null}
    </div>
  )
}

export const AiSettingsPane: FC<AiSettingsPaneProps> = ({
  model,
  defaultChatOpen = false,
  collectionSearchOpen = false,
}) => {
  return (
    <div className="settings-form">
      <section className="settings-section">
        <h2 className="settings-section-header">AI Connections</h2>
        {model.providers.map((provider) => (
          <div key={provider.id} className="ai-connection-row">
            <div className="ai-connection-copy">
              <span className="ai-provider-name">{provider.name}</span>
              <span className="ai-auth-kind">
                {provider.authKind === "oauth" ? "OAuth" : "API Key"}
              </span>
            </div>
            <div className="ai-connection-trailing">
              <ConnectionStatus status={provider.status} />
              <ConnectionAction provider={provider} />
            </div>
          </div>
        ))}
        <p className="footnote ai-connections-footnote">
          Connect AI providers to enable intelligent features in Voyager.
        </p>
      </section>

      <section className="settings-section">
        <h2 className="settings-section-header">AI Model Settings</h2>
        <DisclosureRow
          title="Default Chat"
          summary={model.defaultChatSummary}
          open={defaultChatOpen}
        >
          <ModelSettingsEditor
            provider="Select a provider"
            model="Select a provider first"
            thinking="Provider default"
            resetLabel="Reset to Defaults"
            footnotes={[DEFAULT_CHAT_FOOTER]}
          />
        </DisclosureRow>
        <DisclosureRow
          title="Collection Search"
          summary={model.collectionSearchSummary}
          open={collectionSearchOpen}
        >
          <ModelSettingsEditor
            provider="Auto"
            model="Auto"
            thinking="Provider default"
            resetLabel="Reset to Defaults"
            footnotes={[COLLECTION_SEARCH_FOOTER, COLLECTION_SEARCH_AUTO_EXPLANATION]}
          />
        </DisclosureRow>
      </section>
    </div>
  )
}

AiSettingsPane.displayName = "AiSettingsPane"
