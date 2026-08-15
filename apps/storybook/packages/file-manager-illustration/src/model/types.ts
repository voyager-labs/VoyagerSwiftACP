export type EntryKind = "pdf" | "image" | "folder" | "sheet" | "doc" | "video" | "archive"

/** Public file projection — the only file shape consumers pass. */
export type FileEntry = {
  readonly id: string
  readonly displayName: string
  readonly kind: EntryKind
  readonly extension: string | null
  readonly secondaryLabel: string | null
  readonly thumbnailSrc?: string
}

export type SidebarIconKind = "home" | "folder" | "folder-blue" | "collection" | "chat"

/** Internal breadcrumb segment with SF Symbol name for icon rendering. */
export type BreadcrumbSegment = {
  readonly label: string
  readonly symbolName: string
}

export type SidebarTabItem = {
  readonly id: string
  readonly label: string
  readonly icon: SidebarIconKind
  readonly active?: boolean
  readonly isPinned?: boolean
  readonly secondary?: string
  readonly pageAnchor?: string
  readonly breadcrumb?: readonly BreadcrumbSegment[]
}

export type SidebarTabAction = (item: SidebarTabItem) => void

export type ContentTab = {
  readonly id: string
  readonly label: string
}

export type ContentContext = {
  readonly tabs: readonly ContentTab[]
  readonly activeTabId: string | null
}

export type SelectedEntriesCardProps = {
  readonly count: number
  readonly primaryName: string
}

export type SearchFieldProps = {
  readonly value?: string
  readonly placeholder?: string
  readonly resultCount?: number
}

export type LocationShortcut = {
  readonly id: string
  readonly label: string
  readonly symbolName: string
  readonly iconSrc?: string
}

export type LocationShortcutsProps = {
  readonly shortcuts: readonly LocationShortcut[]
  readonly onSelect?: (shortcut: LocationShortcut) => void
}

export type SidebarSectionProps = {
  readonly items: readonly SidebarTabItem[]
  readonly title?: string
  readonly compact?: boolean
}

export type SidebarIconProps = {
  readonly icon: SidebarIconKind
  readonly isActive?: boolean
}

export type SidebarNavItemProps = {
  readonly item: SidebarTabItem
  readonly actionRevealed?: boolean
  readonly onSelect?: SidebarTabAction
  readonly onUnpin?: SidebarTabAction
  readonly onClose?: SidebarTabAction
}

export type TrafficLightsProps = Record<string, never>

export type ContextMenuAction = {
  readonly id: string
  readonly label: string
  readonly shortcut?: string
  readonly destructive?: boolean
  readonly disabled?: boolean
}

export type Entry = {
  readonly id: string
  readonly name: string
  readonly kind: EntryKind
  readonly meta?: string
  readonly count?: string
  readonly thumbnailSrc?: string
}

// 채팅 도메인 타입 — VoyagerFeaturesAiChat 프레젠테이션 상태의 native → Storybook 번역.
// 원본 경로: apps/macos/Packages/04_Features/AiChat (AiChatViewPresentation, AiChatState).

export type ChatMessage = {
  readonly id: string
  readonly role: "user" | "assistant"
  readonly content: string
  readonly timestamp?: {
    readonly label: string
    readonly isTimestampVisuallySuppressed?: boolean
  }
}

export type ChatFailure = {
  readonly message: string
  readonly recoveryLabel?: string
}

export type ChatStreamingAssistant = {
  readonly title: string
  readonly thinkingLabel?: string
  readonly activityStatusLabel?: string
  readonly content?: string
  readonly failure?: ChatFailure
}

export type ChatSessionRow = {
  readonly id: string
  readonly title: string
  readonly detail?: string
}

export type ChatSessionSection = {
  readonly id: string
  readonly title: string
  readonly rows: readonly ChatSessionRow[]
}

export type ChatConnectionError = {
  readonly title: string
  readonly detail: string
  readonly actionLabel: string
}

export type AiChatInputActionPresentation =
  | {
      readonly kind: "submit"
      readonly isEnabled: boolean
      readonly accessibilityLabel: string
      readonly help: string
    }
  | {
      readonly kind: "stop"
      readonly isEnabled: boolean
      readonly accessibilityLabel: string
      readonly help: string
    }

export type AiChatInputSelectorPresentation = {
  readonly label: string
  readonly accessibilityLabel: string
  readonly accessibilityValue: string
  readonly isDisabled: boolean
}

export type AiChatInputMenuSelectorPresentation = AiChatInputSelectorPresentation & {
  readonly value: string
  readonly options: readonly {
    readonly value: string
    readonly label: string
    readonly detail?: string
    readonly disabled?: boolean
  }[]
}

export type AiChatInputContextItem = {
  readonly id: string
  readonly title: string
  readonly detail?: string
  readonly symbolName?: string
  readonly trailingSymbolName?: string
  readonly isRemovable?: boolean
}

export type AiChatInputContextGroup = {
  readonly id: string
  readonly label: string
  readonly items: readonly AiChatInputContextItem[]
}

export type AiChatInputContextSection = {
  readonly id: string
  readonly kind: "currentResponse" | "nextMessage"
  readonly label: string
  readonly isEditable: boolean
  readonly groups: readonly AiChatInputContextGroup[]
}

export type AiChatInputBarPresentation = {
  readonly placeholder: string
  readonly inputAccessibilityLabel: string
  readonly inputAccessibilityHint: string
  readonly contextAffordanceLabel: string
  readonly modelSelector: AiChatInputMenuSelectorPresentation
  readonly thinkingSelector: AiChatInputMenuSelectorPresentation
  readonly action: AiChatInputActionPresentation
  readonly isComposerEditingDisabled: boolean
  readonly contextSections: readonly AiChatInputContextSection[]
}

export type AiChatAttachmentDropPayload = {
  readonly files: readonly File[]
  readonly urls: readonly URL[]
}

export type AiChatInputBarActions = {
  readonly onAddAttachment?: () => void
  readonly onModelSelected?: (value: string) => void
  readonly onThinkingSelected?: (value: string) => void
  readonly onSubmit?: () => void
  readonly onStop?: () => void
  readonly onRemoveContextItem?: (itemID: string) => void
  readonly onAttachmentsDropped?: (payload: AiChatAttachmentDropPayload) => void
}

export type AiChatInputBarProps = {
  readonly requestText: string
  readonly onRequestTextChange: (value: string) => void
  readonly presentation: AiChatInputBarPresentation
  readonly actions?: AiChatInputBarActions
}

export type ChatSurfaceState =
  | {
      readonly kind: "sessions"
      readonly sections: readonly ChatSessionSection[]
      readonly errorMessage?: string
      readonly isLoading?: boolean
      readonly emptyTitle?: string
      readonly emptyDetail?: string
    }
  | {
      readonly kind: "transcript"
      readonly messages: readonly ChatMessage[]
      readonly inputBar: AiChatInputBarPresentation
      readonly streamingAssistant?: ChatStreamingAssistant
      readonly isProcessing?: boolean
      readonly statusText?: string
      readonly canRegenerate?: boolean
      /** native sessionStatus == .rebindRequired — 최상단 rebind 배너 렌더링 */
      readonly rebindRequired?: boolean
    }
  | {
      readonly kind: "centeredEmpty"
      readonly emptyTitle: string
      readonly emptyDetail: string
      readonly inputBar: AiChatInputBarPresentation
      /** content page의 compactConnectionCTA — unconnected/error surface에서만 표시 */
      readonly connectionError?: ChatConnectionError
    }
  | {
      readonly kind: "unconnected"
      readonly inputBar: AiChatInputBarPresentation
      readonly connectionError: ChatConnectionError
    }
  | {
      readonly kind: "connectionError"
      readonly inputBar: AiChatInputBarPresentation
      readonly connectionError: ChatConnectionError
    }

export type FileManagerIllustrationProps = {
  readonly files: readonly FileEntry[]
  readonly contentContext: ContentContext
  // 생략 시 inspector는 기본 composer-only 본문을 렌더링한다. 지정 시 해당 채팅 프레젠테이션(sessions/transcript/empty/unconnected/streaming/error/recovery)을 root에서 재현한다.
  readonly chatSurface?: ChatSurfaceState
  readonly chatInputActions?: AiChatInputBarActions
  readonly chatOnErrorRecovery?: () => void
  readonly chatOnRebindContext?: () => void
  readonly chatOnStartNewChat?: () => void
}
