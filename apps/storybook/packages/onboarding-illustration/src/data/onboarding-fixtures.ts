import type { OnboardingState, PermissionState, ProviderState } from "../model"

const blockedPermissions: PermissionState = {
  fullDiskAccess: "Needs Action",
  fullDiskAccessMessage: "Turn on Full Disk Access to keep going.",
  folders: [
    { title: "Desktop", status: "Not Granted" },
    { title: "Documents", status: "Not Granted" },
    { title: "Downloads", status: "Not Granted" },
  ],
  folderMessage: "Tap Grant Access when you're ready.",
  isRequestingFolders: false,
  launchAtLogin: true,
}

const grantedPermissions: PermissionState = {
  fullDiskAccess: "Granted",
  fullDiskAccessMessage: "You're all set for Full Disk Access.",
  folders: [
    { title: "Desktop", status: "Granted" },
    { title: "Documents", status: "Granted" },
    { title: "Downloads", status: "Granted" },
  ],
  folderMessage: "Access granted for Voyager Helper (Desktop, Documents, Downloads).",
  isRequestingFolders: false,
  launchAtLogin: true,
}

const providers: readonly ProviderState[] = [
  {
    id: "codex",
    displayName: "ChatGPT Codex",
    authMethod: "OAuth",
    status: "Connected",
  },
  {
    id: "openai",
    displayName: "OpenAI",
    authMethod: "API Key",
    status: "Not connected",
    enteredKey: "",
  },
  {
    id: "anthropic",
    displayName: "Anthropic",
    authMethod: "API Key",
    status: "Failed",
    reason: "Invalid API key.",
    enteredKey: "••••••••••••",
  },
]

const baseState: OnboardingState = {
  step: "welcome",
  permissions: blockedPermissions,
  aiPhase: "ready",
  providers,
  completePhase: "idle",
}

export const welcomeState: OnboardingState = baseState

export const permissionsBlockedState: OnboardingState = {
  ...baseState,
  step: "permissions",
}

export const permissionsRequestingState: OnboardingState = {
  ...permissionsBlockedState,
  permissions: {
    ...blockedPermissions,
    isRequestingFolders: true,
    folderMessage: "Requesting access…",
  },
}

export const permissionsGrantedState: OnboardingState = {
  ...baseState,
  step: "permissions",
  permissions: grantedPermissions,
}

export const aiProvidersState: OnboardingState = {
  ...baseState,
  step: "aiProvider",
  permissions: grantedPermissions,
}

export const aiLoadingState: OnboardingState = {
  ...aiProvidersState,
  aiPhase: "loading",
}

export const aiErrorState: OnboardingState = {
  ...aiProvidersState,
  aiPhase: "error",
  aiError: "Unable to load AI providers.",
}

export const completeState: OnboardingState = {
  ...aiProvidersState,
  step: "complete",
}

export const completeOpeningState: OnboardingState = {
  ...completeState,
  completePhase: "opening",
}

export const completeErrorState: OnboardingState = {
  ...completeState,
  completePhase: "error",
}
