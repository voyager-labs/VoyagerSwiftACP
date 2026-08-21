export type OnboardingStep = "welcome" | "permissions" | "aiProvider" | "complete"

export type PermissionStatus = "Granted" | "Needs Action" | "Denied" | "Unknown"
export type FolderStatus = "Granted" | "Not Granted"
export type AiPhase = "loading" | "error" | "ready"
export type ProviderStatus =
  | "Not connected"
  | "Connecting…"
  | "Checking status…"
  | "Connected"
  | "Failed"
  | "Disconnecting…"
  | "Unavailable"
export type CompletePhase = "idle" | "opening" | "error"

export interface FolderAccessItem {
  readonly title: "Desktop" | "Documents" | "Downloads"
  readonly status: FolderStatus
}

export interface PermissionState {
  readonly fullDiskAccess: PermissionStatus
  readonly fullDiskAccessMessage: string
  readonly folders: readonly FolderAccessItem[]
  readonly folderMessage: string
  readonly isRequestingFolders: boolean
  readonly launchAtLogin: boolean
}

export interface ProviderState {
  readonly id: "codex" | "openai" | "anthropic"
  readonly displayName: string
  readonly authMethod: "OAuth" | "API Key"
  readonly status: ProviderStatus
  readonly reason?: string
  readonly enteredKey?: string
}

export interface OnboardingState {
  readonly step: OnboardingStep
  readonly permissions: PermissionState
  readonly aiPhase: AiPhase
  readonly aiError?: string
  readonly providers: readonly ProviderState[]
  readonly completePhase: CompletePhase
}

export interface OnboardingWindowProps {
  readonly state: OnboardingState
}
