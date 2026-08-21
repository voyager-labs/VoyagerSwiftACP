import { Button, TextField, Toggle } from "@voyager-labs/design-foundation"
import type { FC } from "react"
import type { OnboardingState, PermissionState, ProviderState } from "./model"

interface PermissionsStepProps {
  readonly state: PermissionState
}

export const PermissionsStep: FC<PermissionsStepProps> = ({ state }) => {
  const allFoldersGranted = state.folders.every(({ status }) => status === "Granted")
  const fdaGranted = state.fullDiskAccess === "Granted"

  return (
    <div className="onb-card-stack">
      <section className="onb-card">
        <div className="onb-card-heading">
          <h2>Full Disk Access</h2>
          <strong className={fdaGranted ? "is-success" : ""}>{state.fullDiskAccess}</strong>
        </div>
        <p>{state.fullDiskAccessMessage}</p>
        <small>Go to System Settings &gt; Privacy &amp; Security &gt; Full Disk Access.</small>
        {!fdaGranted ? <Button>Open System Settings</Button> : null}
      </section>

      <section className="onb-card">
        <h2>Files &amp; Folders</h2>
        <p>Let Voyager Helper access Desktop, Documents, and Downloads.</p>
        <small>macOS will ask. Choose Allow.</small>
        <div className="onb-inline-action">
          <Button disabled={state.isRequestingFolders || allFoldersGranted}>
            {allFoldersGranted ? "Done" : "Grant Access"}
          </Button>
          {state.isRequestingFolders ? (
            <span className="onb-spinner" aria-label="Requesting access" />
          ) : null}
        </div>
        <small>{state.folderMessage}</small>
        <div className="onb-folder-list">
          <strong>Voyager Helper</strong>
          {state.folders.map((folder) => (
            <div className="onb-folder-row" key={folder.title}>
              <span>{folder.title}</span>
              <strong>{folder.status}</strong>
            </div>
          ))}
        </div>
      </section>

      <section className="onb-card onb-toggle-row">
        <h2>Launch at Login</h2>
        <Toggle checked={state.launchAtLogin} onChange={() => undefined} />
      </section>
    </div>
  )
}

interface AiProviderStepProps {
  readonly state: OnboardingState
}

function providerAction(provider: ProviderState) {
  if (provider.status === "Connected" || provider.status === "Unavailable") {
    return null
  }
  if (provider.status === "Connecting…") {
    return <Button>Cancel</Button>
  }
  if (provider.status === "Checking status…" || provider.status === "Disconnecting…") {
    return null
  }
  const label = provider.status === "Failed" ? "Retry" : "Connect"
  if (provider.authMethod === "OAuth") {
    return <Button variant="primary">{label}</Button>
  }
  return (
    <div className="onb-provider-action">
      <TextField
        value={provider.enteredKey}
        placeholder="API key"
        ariaLabel={`${provider.displayName} API key`}
        variant="rounded"
      />
      <Button variant="primary" disabled={!provider.enteredKey}>
        {label}
      </Button>
    </div>
  )
}

export const AiProviderStep: FC<AiProviderStepProps> = ({ state }) => (
  <div className="onb-ai-step">
    <header>
      <h2>AI Provider Setup</h2>
      <p>Connect a provider now or set it up later.</p>
    </header>

    {state.aiPhase === "loading" ? (
      <div className="onb-loading-row">
        <span className="onb-spinner" aria-hidden="true" />
        <span>Loading AI providers…</span>
      </div>
    ) : null}

    {state.aiPhase === "error" ? (
      <div className="onb-load-error">
        <p>{state.aiError}</p>
        <div className="onb-inline-action">
          <Button variant="primary">Retry</Button>
          <Button>Set up later</Button>
        </div>
      </div>
    ) : null}

    {state.aiPhase === "ready" ? (
      <div className="onb-provider-list">
        {state.providers.map((provider) => (
          <section className="onb-provider-card" key={provider.id}>
            <div className="onb-provider-heading">
              <div>
                <h3>{provider.displayName}</h3>
                <small>{provider.authMethod}</small>
              </div>
              <strong data-status={provider.status}>{provider.status}</strong>
            </div>
            {provider.reason ? <small>{provider.reason}</small> : null}
            {providerAction(provider)}
          </section>
        ))}
      </div>
    ) : null}

    <div className="onb-skip-action">
      <Button disabled={state.step === "complete"}>Set up later</Button>
    </div>
  </div>
)

interface CompleteStepProps {
  readonly phase: OnboardingState["completePhase"]
}

export const CompleteStep: FC<CompleteStepProps> = ({ phase }) => (
  <div className="onb-complete-step">
    {phase === "opening" ? (
      <span className="onb-spinner" aria-label="Opening file manager" />
    ) : null}
    {phase === "error" ? (
      <>
        <p>We couldn't open a file manager window. Please try again.</p>
        <Button>Retry</Button>
      </>
    ) : null}
  </div>
)
