export type HomeFavorite = {
  readonly id: string
  readonly label: string
  readonly glyph: string
  readonly destinationTabId: "directory" | "collection"
  readonly pageAnchor: string
}

export type HomeLocation = {
  readonly id: string
  readonly label: string
  readonly glyph: string
  readonly destinationTabId: "directory"
  readonly path: string
}

export type HomeRecentChat = {
  readonly id: string
  readonly sessionId: string
  readonly title: string
  readonly detail?: string
  readonly updatedLabel: string
  readonly destinationTabId: "ai-chat"
}
