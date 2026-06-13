import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi

extension AiChatFeature {
    func updateCurrentContextFolderStructureMode(_ mode: AiChatFolderStructureMode, state: inout State) {
        let currentContextKeys = currentContextFolderStructureKeys(for: state.currentContext)
        let targetKeys = mode == .includeSubfolders
            ? pruningFolderStructureKeysCoveredByRecursiveParents(currentContextKeys)
            : currentContextKeys
        let coveredKeys = Set(currentContextKeys).subtracting(targetKeys)
        for key in coveredKeys {
            state.currentContextFolderStructureModes.removeValue(forKey: key)
        }
        for key in targetKeys {
            state.currentContextFolderStructureModes[key] = mode
        }
        state.currentContext = currentContextSnapshot(
            state.currentContext,
            excluding: state.addedAttachments,
            applyingFolderStructureModes: state.currentContextFolderStructureModes,
        )
    }

    func removeCurrentContextDuplicates(state: inout State) {
        let currentContext = currentContextSnapshot(
            state.currentContext,
            excluding: state.addedAttachments,
            applyingFolderStructureModes: state.currentContextFolderStructureModes,
        )
        ensureCurrentFolderStructureModeDefaults(
            for: currentContext,
            in: &state.currentContextFolderStructureModes,
        )
        state.currentContext = applyFolderStructureModes(
            state.currentContextFolderStructureModes,
            to: currentContext,
        )
    }

    func ensureCurrentFolderStructureModeDefaults(
        for snapshot: AiChatCurrentContextSnapshot,
        in folderStructureModes: inout [AiChatCurrentContextFolderStructureKey: AiChatFolderStructureMode],
    ) {
        for key in currentContextFolderStructureKeys(for: snapshot) where folderStructureModes[key] == nil {
            let isCoveredByRecursiveFolder = folderStructureModes.contains { parentKey, mode in
                mode == .includeSubfolders && recursiveFolderStructureKey(parentKey, covers: key)
            }
            guard !isCoveredByRecursiveFolder else { continue }
            folderStructureModes[key] = .currentFolderOnly
        }
    }

    func pruningFolderStructureKeysCoveredByRecursiveParents(
        _ keys: [AiChatCurrentContextFolderStructureKey],
    ) -> [AiChatCurrentContextFolderStructureKey] {
        keys.filter { key in
            !keys.contains { parentKey in
                recursiveFolderStructureKey(parentKey, covers: key)
            }
        }
    }

    func recursiveFolderStructureKey(
        _ parentKey: AiChatCurrentContextFolderStructureKey,
        covers key: AiChatCurrentContextFolderStructureKey,
    ) -> Bool {
        let parentPath = parentKey.canonicalPath.hasSuffix("/")
            ? String(parentKey.canonicalPath.dropLast())
            : parentKey.canonicalPath
        let childPath = key.canonicalPath.hasSuffix("/")
            ? String(key.canonicalPath.dropLast())
            : key.canonicalPath
        guard parentPath != childPath else { return false }
        return childPath.hasPrefix(parentPath + "/")
    }

    func currentContextSnapshot(
        _ snapshot: AiChatCurrentContextSnapshot,
        excluding attachments: [AiChatAttachmentDraft],
        applyingFolderStructureModes folderStructureModes: [
            AiChatCurrentContextFolderStructureKey: AiChatFolderStructureMode
        ],
    ) -> AiChatCurrentContextSnapshot {
        let attachmentPaths = Set(attachments.compactMap(normalizedAttachmentPath(for:)))
        let references = attachmentPaths.isEmpty
            ? snapshot.references
            : snapshot.references.filter { reference in
                !currentContextPaths(for: reference).contains(where: { attachmentPaths.contains($0) })
            }
        let items = attachmentPaths.isEmpty
            ? snapshot.items
            : snapshot.items.compactMap { item -> AiChatContextItem? in
                guard !currentContextPaths(for: item).contains(where: { attachmentPaths.contains($0) }) else {
                    return nil
                }
                let itemReferences = item.references.filter { reference in
                    !currentContextPaths(for: reference).contains(where: { attachmentPaths.contains($0) })
                }
                return AiChatContextItem(
                    kind: item.kind,
                    identifier: item.identifier,
                    title: item.title,
                    subtitle: item.subtitle,
                    metadata: item.metadata,
                    references: itemReferences,
                )
            }
        let contextAttachments = attachmentPaths.isEmpty
            ? snapshot.attachments
            : snapshot.attachments.filter { attachment in
                !currentContextPaths(for: attachment).contains(where: { attachmentPaths.contains($0) })
            }

        let filteredSnapshot = references.count == snapshot.references.count
            && items.count == snapshot.items.count
            && contextAttachments.count == snapshot.attachments.count
            ? snapshot
            : AiChatCurrentContextSnapshot(
                summary: currentContextSummary(references: references, items: items, attachments: contextAttachments),
                references: references,
                items: items,
                attachments: contextAttachments,
            )
        return applyFolderStructureModes(folderStructureModes, to: filteredSnapshot)
    }

    func applyFolderStructureModes(
        _ folderStructureModes: [AiChatCurrentContextFolderStructureKey: AiChatFolderStructureMode],
        to snapshot: AiChatCurrentContextSnapshot,
    ) -> AiChatCurrentContextSnapshot {
        guard !folderStructureModes.isEmpty else {
            return clearFolderStructureModeMetadata(from: snapshot)
        }

        let references = snapshot.references.map { reference in
            applyFolderStructureMode(folderStructureModes, to: reference)
        }
        let items = snapshot.items.map { item in
            applyFolderStructureMode(folderStructureModes, to: item)
        }
        let attachments = snapshot.attachments.map { attachment in
            applyFolderStructureMode(folderStructureModes, to: attachment)
        }
        return AiChatCurrentContextSnapshot(
            summary: snapshot.summary,
            references: references,
            items: items,
            attachments: attachments,
        )
    }

    func clearFolderStructureModeMetadata(from snapshot: AiChatCurrentContextSnapshot) -> AiChatCurrentContextSnapshot {
        let references = snapshot.references.map { reference in
            removeFolderStructureModeMetadata(from: reference)
        }
        let items = snapshot.items.map { item in
            removeFolderStructureModeMetadata(from: item)
        }
        let attachments = snapshot.attachments.map { attachment in
            removeFolderStructureModeMetadata(from: attachment)
        }
        return AiChatCurrentContextSnapshot(
            summary: snapshot.summary,
            references: references,
            items: items,
            attachments: attachments,
        )
    }

    func applyFolderStructureMode(
        _ folderStructureModes: [AiChatCurrentContextFolderStructureKey: AiChatFolderStructureMode],
        to reference: AiChatContextReference,
    ) -> AiChatContextReference {
        let metadata = applyingFolderStructureModeMetadata(
            folderStructureModes,
            lookupContext: .init(
                source: .reference,
                kind: reference.kind,
                identifier: reference.identifier,
                subtitle: reference.subtitle,
            ),
            metadata: reference.metadata,
        )
        return AiChatContextReference(
            kind: reference.kind,
            identifier: reference.identifier,
            title: reference.title,
            subtitle: reference.subtitle,
            metadata: metadata,
        )
    }

    func applyFolderStructureMode(
        _ folderStructureModes: [AiChatCurrentContextFolderStructureKey: AiChatFolderStructureMode],
        to item: AiChatContextItem,
    ) -> AiChatContextItem {
        let metadata = applyingFolderStructureModeMetadata(
            folderStructureModes,
            lookupContext: .init(source: .item, kind: item.kind, identifier: item.identifier, subtitle: item.subtitle),
            metadata: item.metadata,
        )
        return AiChatContextItem(
            kind: item.kind,
            identifier: item.identifier,
            title: item.title,
            subtitle: item.subtitle,
            metadata: metadata,
            references: item.references.map { reference in
                let metadata = applyingFolderStructureModeMetadata(
                    folderStructureModes,
                    lookupContext: .init(
                        source: .itemReference,
                        kind: reference.kind,
                        identifier: reference.identifier,
                        subtitle: reference.subtitle,
                    ),
                    metadata: reference.metadata,
                )
                return AiChatContextReference(
                    kind: reference.kind,
                    identifier: reference.identifier,
                    title: reference.title,
                    subtitle: reference.subtitle,
                    metadata: metadata,
                )
            },
        )
    }

    func applyFolderStructureMode(
        _ folderStructureModes: [AiChatCurrentContextFolderStructureKey: AiChatFolderStructureMode],
        to attachment: AiChatContextAttachment,
    ) -> AiChatContextAttachment {
        let metadata = applyingFolderStructureModeMetadata(
            folderStructureModes,
            lookupContext: .init(
                source: .attachment,
                kind: attachment.kind,
                identifier: attachment.identifier,
                subtitle: attachment.subtitle,
            ),
            metadata: attachment.metadata,
        )
        return AiChatContextAttachment(
            identifier: attachment.identifier,
            title: attachment.title,
            subtitle: attachment.subtitle,
            kind: attachment.kind,
            metadata: metadata,
        )
    }

    func removeFolderStructureModeMetadata(from reference: AiChatContextReference) -> AiChatContextReference {
        AiChatContextReference(
            kind: reference.kind,
            identifier: reference.identifier,
            title: reference.title,
            subtitle: reference.subtitle,
            metadata: removingFolderStructureModeMetadata(from: reference.metadata),
        )
    }

    func removeFolderStructureModeMetadata(from item: AiChatContextItem) -> AiChatContextItem {
        AiChatContextItem(
            kind: item.kind,
            identifier: item.identifier,
            title: item.title,
            subtitle: item.subtitle,
            metadata: removingFolderStructureModeMetadata(from: item.metadata),
            references: item.references.map(removeFolderStructureModeMetadata),
        )
    }

    func removeFolderStructureModeMetadata(from attachment: AiChatContextAttachment) -> AiChatContextAttachment {
        AiChatContextAttachment(
            identifier: attachment.identifier,
            title: attachment.title,
            subtitle: attachment.subtitle,
            kind: attachment.kind,
            metadata: removingFolderStructureModeMetadata(from: attachment.metadata),
        )
    }

    struct FolderStructureLookupContext {
        var source: AiChatCurrentContextFolderStructureSource
        var kind: AiChatContextItemKind
        var identifier: String
        var subtitle: String?
    }

    func applyingFolderStructureModeMetadata(
        _ folderStructureModes: [AiChatCurrentContextFolderStructureKey: AiChatFolderStructureMode],
        lookupContext: FolderStructureLookupContext,
        metadata: [String: String],
    ) -> [String: String] {
        var metadata = removingFolderStructureModeMetadata(from: metadata)
        let keys = currentContextFolderStructureKeys(
            source: lookupContext.source,
            kind: lookupContext.kind,
            metadata: metadata,
            identifier: lookupContext.identifier,
            subtitle: lookupContext.subtitle,
        )
        let mode = folderStructureModes.first(where: { key, _ in keys.contains(key) })?.value
        if let mode {
            metadata["folderStructureMode"] = mode.rawValue
        }
        return metadata
    }

    func removingFolderStructureModeMetadata(from metadata: [String: String]) -> [String: String] {
        var metadata = metadata
        metadata.removeValue(forKey: "folderStructureMode")
        return metadata
    }

    func currentContextPaths(from metadata: [String: String], identifier: String, subtitle: String?) -> [String] {
        normalizedCurrentContextPaths(metadata: metadata, identifier: identifier, subtitle: subtitle)
    }

    func updateAttachmentFolderStructureMode(
        _ mode: AiChatFolderStructureMode,
        for attachment: AiChatAttachmentDraft,
    ) -> AiChatAttachmentDraft {
        var metadata = attachment.metadata
        metadata["folderStructureMode"] = mode.rawValue
        return AiChatAttachmentDraft(
            id: attachment.id,
            source: attachment.source,
            displayTitle: attachment.displayTitle,
            subtitle: attachment.subtitle,
            kind: attachment.kind,
            sourceLocation: attachment.sourceLocation,
            metadata: metadata,
            currentStatus: attachment.currentStatus,
        )
    }

    func currentContextSummary(
        references: [AiChatContextReference],
        items: [AiChatContextItem],
        attachments: [AiChatContextAttachment],
    ) -> String? {
        if items.count == 1 {
            return items[0].title ?? currentContextDisplayName(from: items[0].identifier)
        }
        if items.count > 1 {
            return "\(items.count) selected"
        }
        if let reference = references.first {
            return reference.title ?? currentContextDisplayName(from: reference.identifier)
        }
        if let attachment = attachments.first {
            return attachment.title ?? currentContextDisplayName(from: attachment.identifier)
        }
        return nil
    }

    func currentContextPaths(for reference: AiChatContextReference) -> [String] {
        normalizedCurrentContextPaths(
            metadata: reference.metadata,
            identifier: reference.identifier,
            subtitle: reference.subtitle,
        )
    }

    func currentContextPaths(for item: AiChatContextItem) -> [String] {
        normalizedCurrentContextPaths(
            metadata: item.metadata,
            identifier: item.identifier,
            subtitle: item.subtitle,
        )
    }

    func currentContextPaths(for attachment: AiChatContextAttachment) -> [String] {
        normalizedCurrentContextPaths(
            metadata: attachment.metadata,
            identifier: attachment.identifier,
            subtitle: attachment.subtitle,
        )
    }

    func normalizedCurrentContextPaths(
        metadata: [String: String],
        identifier: String,
        subtitle: String?,
    ) -> [String] {
        var paths: [String] = []
        for value in [metadata["path"], metadata["filePath"], subtitle, identifier].compactMap(\.self) {
            guard let path = normalizedCurrentContextPath(from: value), !paths.contains(path) else { continue }
            paths.append(path)
        }
        return paths
    }

    func normalizedCurrentContextPath(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }
        return normalizedFileURL(from: URL(fileURLWithPath: trimmed))?.path(percentEncoded: false)
    }

    func currentContextDisplayName(from value: String) -> String {
        guard let path = normalizedCurrentContextPath(from: value) else { return value }
        let lastPathComponent = URL(fileURLWithPath: path).lastPathComponent
        return lastPathComponent.isEmpty ? path : lastPathComponent
    }
}
