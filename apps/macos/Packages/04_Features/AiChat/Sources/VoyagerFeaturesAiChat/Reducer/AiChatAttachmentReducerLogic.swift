import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers
import VoyagerEntitiesAi

extension AiChatFeature {
    func loadDroppedAttachmentURLs(
        from providers: [AiChatAttachmentDropProvider],
        originSessionID: AiChatSessionID,
    ) -> Effect<Action> {
        .run { send in
            var urls: [URL] = []
            for droppedProvider in providers {
                if droppedProvider.provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
                   let url = await Self.droppedFileURL(
                       from: droppedProvider.provider,
                       typeIdentifier: UTType.fileURL.identifier,
                   )
                {
                    urls.append(url)
                } else if droppedProvider.provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                          let url = await Self.droppedFileURL(
                              from: droppedProvider.provider,
                              typeIdentifier: UTType.url.identifier,
                          )
                {
                    urls.append(url)
                }
            }
            guard !urls.isEmpty else { return }
            await send(.attachmentDropSelection(originSessionID, urls))
        }
        .cancellable(id: CancelID.attachmentDrop(originSessionID), cancelInFlight: true)
    }

    static func droppedFileURL(from provider: NSItemProvider, typeIdentifier: String) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                continuation.resume(returning: Self.droppedFileURL(from: item))
            }
        }
    }

    nonisolated static func droppedFileURL(from item: (any NSSecureCoding)?) -> URL? {
        if let url = item as? URL, url.isFileURL {
            return url
        }
        if let data = item as? Data,
           let url = URL(dataRepresentation: data, relativeTo: nil),
           url.isFileURL
        {
            return url
        }
        if let string = item as? String,
           let url = URL(string: string),
           url.isFileURL
        {
            return url
        }
        return nil
    }

    @discardableResult
    func addAttachmentDrafts(
        from urls: [URL],
        skippingCurrentContextDuplicates: Bool,
        state: inout State,
    ) -> Bool {
        var didAddAttachments = false
        var knownPaths = Set(state.addedAttachments.compactMap(normalizedAttachmentPath(for:)))
        let currentContextPaths = skippingCurrentContextDuplicates
            ? Set(currentContextPaths(for: state.currentContext))
            : []

        for url in urls {
            guard let draft = makeAttachmentDraft(from: url) else { continue }
            let normalizedPath = normalizedAttachmentPath(for: draft) ?? draft.id.rawValue
            guard !currentContextPaths.contains(normalizedPath) else { continue }
            guard knownPaths.insert(normalizedPath).inserted else { continue }
            state.addedAttachments.append(draft)
            didAddAttachments = true
        }
        if didAddAttachments {
            state.markPreparedTransientSessionAsTouched()
        }
        return didAddAttachments
    }

    func currentContextPaths(for snapshot: AiChatCurrentContextSnapshot) -> [String] {
        var paths: [String] = []
        for reference in snapshot.references {
            appendUnique(currentContextPaths(for: reference), to: &paths)
        }
        for item in snapshot.items {
            appendUnique(currentContextPaths(for: item), to: &paths)
            for reference in item.references {
                appendUnique(currentContextPaths(for: reference), to: &paths)
            }
        }
        for attachment in snapshot.attachments {
            appendUnique(currentContextPaths(for: attachment), to: &paths)
        }
        return paths
    }

    func currentContextFolderStructureKeys(for snapshot: AiChatCurrentContextSnapshot)
        -> [AiChatCurrentContextFolderStructureKey]
    {
        var keys: [AiChatCurrentContextFolderStructureKey] = []
        for reference in snapshot.references {
            appendUnique(currentContextFolderStructureKeys(
                source: .reference,
                kind: reference.kind,
                metadata: reference.metadata,
                identifier: reference.identifier,
                subtitle: reference.subtitle,
            ), to: &keys)
        }
        for item in snapshot.items {
            appendUnique(currentContextFolderStructureKeys(
                source: .item,
                kind: item.kind,
                metadata: item.metadata,
                identifier: item.identifier,
                subtitle: item.subtitle,
            ), to: &keys)
            for reference in item.references {
                appendUnique(currentContextFolderStructureKeys(
                    source: .itemReference,
                    kind: reference.kind,
                    metadata: reference.metadata,
                    identifier: reference.identifier,
                    subtitle: reference.subtitle,
                ), to: &keys)
            }
        }
        for attachment in snapshot.attachments {
            appendUnique(currentContextFolderStructureKeys(
                source: .attachment,
                kind: attachment.kind,
                metadata: attachment.metadata,
                identifier: attachment.identifier,
                subtitle: attachment.subtitle,
            ), to: &keys)
        }
        return keys
    }

    func currentContextFolderStructureKeys(
        source: AiChatCurrentContextFolderStructureSource,
        kind: AiChatContextItemKind,
        metadata: [String: String],
        identifier: String,
        subtitle: String?,
    ) -> [AiChatCurrentContextFolderStructureKey] {
        guard supportsFolderStructureMode(kind: kind, metadata: metadata, identifier: identifier, subtitle: subtitle)
        else {
            return []
        }
        return normalizedCurrentContextPaths(metadata: metadata, identifier: identifier, subtitle: subtitle)
            .map { path in
                AiChatCurrentContextFolderStructureKey(source: source, canonicalPath: path)
            }
    }

    func supportsFolderStructureMode(
        kind: AiChatContextItemKind,
        metadata: [String: String],
        identifier: String,
        subtitle: String?,
    ) -> Bool {
        kind == .folder
            || metadata["route"] == "folder"
            || metadata["kind"] == "folder"
            || metadata["fileKind"] == "folder"
            || normalizedCurrentContextPaths(metadata: metadata, identifier: identifier, subtitle: subtitle)
            .contains(where: pathIsDirectory)
    }

    func pathIsDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    func appendUnique(
        _ newKeys: [AiChatCurrentContextFolderStructureKey],
        to keys: inout [AiChatCurrentContextFolderStructureKey],
    ) {
        for key in newKeys where !keys.contains(key) {
            keys.append(key)
        }
    }

    func appendUnique(_ newPaths: [String], to paths: inout [String]) {
        for path in newPaths where !paths.contains(path) {
            paths.append(path)
        }
    }

    func removeAddedAttachment(_ id: AiChatAttachmentID, state: inout State) {
        let previousCount = state.addedAttachments.count
        state.addedAttachments.removeAll { $0.id == id }
        if state.addedAttachments.count != previousCount {
            state.markPreparedTransientSessionAsTouched()
        }
    }

    func makeAttachmentDraft(from url: URL) -> AiChatAttachmentDraft? {
        guard let normalizedURL = normalizedFileURL(from: url) else { return nil }
        let normalizedPath = normalizedURL.path(percentEncoded: false)
        guard !normalizedPath.isEmpty else { return nil }

        var metadata: [String: String] = [:]
        if attachmentSource(for: normalizedURL) == .folder {
            metadata["folderStructureMode"] = AiChatFolderStructureMode.currentFolderOnly.rawValue
        }

        return AiChatAttachmentDraft(
            id: AiChatAttachmentID(rawValue: normalizedPath),
            source: attachmentSource(for: normalizedURL),
            displayTitle: normalizedURL.lastPathComponent.isEmpty ? nil : normalizedURL.lastPathComponent,
            sourceLocation: AiChatAttachmentSourceLocation(fileURL: normalizedURL, filePath: normalizedPath),
            metadata: metadata,
        )
    }

    func normalizedAttachmentPath(for draft: AiChatAttachmentDraft) -> String? {
        if let fileURL = draft.sourceLocation.fileURL, let normalizedURL = normalizedFileURL(from: fileURL) {
            let path = normalizedURL.path(percentEncoded: false)
            if !path.isEmpty { return path }
        }
        if let filePath = draft.sourceLocation.filePath,
           let normalizedURL = normalizedFileURL(from: URL(fileURLWithPath: filePath))
        {
            let path = normalizedURL.path(percentEncoded: false)
            if !path.isEmpty { return path }
        }
        return nil
    }

    func normalizedFileURL(from url: URL) -> URL? {
        guard url.isFileURL else { return nil }
        return url.resolvingSymlinksInPath().standardizedFileURL
    }

    func cleanupEligibleEmptyDraftSessionID(for state: State) -> AiChatSessionID? {
        guard let emptyDraftSessionID = state.emptyDraftSessionID,
              let sessionID = state.sessionID,
              emptyDraftSessionID == sessionID,
              state.sessionStatus == .idle,
              state.transcriptHistory.isEmpty,
              state.streamingAssistantDraft == nil,
              state.lastRequestContext == nil
        else { return nil }

        return emptyDraftSessionID
    }

    func attachmentSource(for url: URL) -> AiChatAttachmentSource {
        let pathExtension = url.pathExtension.lowercased()
        if pathExtension == "voycoll" {
            return .collectionDocument
        }
        if url.hasDirectoryPath {
            return .folder
        }
        return .file
    }
}
