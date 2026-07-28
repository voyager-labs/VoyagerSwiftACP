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
