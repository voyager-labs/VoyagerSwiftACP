import type { FC } from "react"
import type { EntryKind } from "../../model/types"
import { ArchiveIcon } from "./entry-icons/ArchiveIcon"
import { FileIcon } from "./entry-icons/FileIcon"
import { FolderIcon } from "./entry-icons/FolderIcon"
import { ImageIcon } from "./entry-icons/ImageIcon"
import { PdfIcon } from "./entry-icons/PdfIcon"
import { SheetIcon } from "./entry-icons/SheetIcon"
import { VideoIcon } from "./entry-icons/VideoIcon"

export interface EntryThumbnailEntry {
  readonly id: string
  readonly kind: EntryKind
  readonly thumbnailSrc?: string
}

export interface EntryThumbnailProps {
  entry: EntryThumbnailEntry
  size?: "regular" | "small"
}

export const EntryThumbnail: FC<EntryThumbnailProps> = ({ entry, size = "regular" }) => {
  const className = ["thumb", size === "small" ? "thumb-small" : "", `thumb-${entry.kind}`]
    .filter(Boolean)
    .join(" ")

  return (
    <span className={className} aria-hidden="true">
      {entry.thumbnailSrc ? (
        <img
          className="entry-thumbnail-image"
          src={entry.thumbnailSrc}
          alt=""
          width={64}
          height={64}
          draggable={false}
        />
      ) : entry.kind === "folder" ? (
        <FolderIcon />
      ) : entry.kind === "image" ? (
        <ImageIcon />
      ) : entry.kind === "pdf" ? (
        <PdfIcon />
      ) : entry.kind === "sheet" ? (
        <SheetIcon />
      ) : entry.kind === "video" ? (
        <VideoIcon />
      ) : entry.kind === "archive" ? (
        <ArchiveIcon />
      ) : (
        <FileIcon accent="neutral" kind="doc" label="DOC" />
      )}
    </span>
  )
}

EntryThumbnail.displayName = "EntryThumbnail"
