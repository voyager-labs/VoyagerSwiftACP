import Foundation
import VoyagerEntitiesAi

extension AiChatFeature {
    func makeRequestContextResolverInput(
        for pendingRequest: AiChatPendingRequestStart,
        state: State,
    ) -> AiChatContextPartResolverInput {
        let selectedModel = pendingRequest.selectedModel
        let requestFamily = aiChatRequestFamily(for: selectedModel.provider)
        let sourceContext = pendingRequest.preparedRequest.requestContextSource

        return AiChatContextPartResolverInput(
            provider: selectedModel.provider,
            rawModelID: selectedModel.rawModelID,
            requestFamily: requestFamily,
            currentContext: sourceContext?.currentContext ?? state.currentContext,
            attachments: sourceContext?.addedAttachments.map(AiChatAttachmentDraft.init(snapshot:)) ?? state
                .addedAttachments,
        )
    }

    func makeLockedRequestContextSnapshot(
        from resolvedContext: AiChatResolvedRequestContext,
    ) -> AiChatLockedRequestContextSnapshot {
        AiChatLockedRequestContextSnapshot(
            currentContext: resolvedContext.currentContext,
            addedAttachments: resolvedContext.addedAttachments.map(requestSummaryAttachmentSnapshot),
            parts: resolvedContext.parts.map { part in
                AiChatLockedContextPartSnapshot(
                    source: part.source == .attachment ? .attachment : .currentContext,
                    resolution: part.resolution,
                    canonicalPath: part.canonicalPath,
                    displayPath: part.displayPath,
                    fileKind: part.fileKind,
                    displayTitle: part.displayTitle,
                    byteCount: part.byteCount,
                    mimeType: part.mimeType,
                )
            },
        )
    }

    func persistenceSafeRequestContext(
        _ context: AiChatLockedRequestContextSnapshot,
    ) -> AiChatLockedRequestContextSnapshot {
        AiChatLockedRequestContextSnapshot(
            currentContext: persistenceSafeCurrentContext(context.currentContext),
            addedAttachments: context.addedAttachments.map(persistenceSafeAttachmentSnapshot),
            parts: context.parts.map(persistenceSafeContextPart),
            status: context.status,
        )
    }

    func persistenceSafeCurrentContext(
        _ snapshot: AiChatCurrentContextSnapshot,
    ) -> AiChatCurrentContextSnapshot {
        AiChatCurrentContextSnapshot(
            summary: snapshot.summary,
            references: snapshot.references.map(persistenceSafeContextReference),
            items: snapshot.items.map(persistenceSafeContextItem),
            attachments: snapshot.attachments.map(persistenceSafeContextAttachment),
        )
    }

    func persistenceSafeContextReference(
        _ reference: AiChatContextReference,
    ) -> AiChatContextReference {
        AiChatContextReference(
            kind: reference.kind,
            identifier: reference.identifier,
            title: reference.title,
            subtitle: reference.subtitle,
            metadata: persistenceSafeMetadata(reference.metadata),
        )
    }

    func persistenceSafeContextItem(_ item: AiChatContextItem) -> AiChatContextItem {
        AiChatContextItem(
            kind: item.kind,
            identifier: item.identifier,
            title: item.title,
            subtitle: item.subtitle,
            metadata: persistenceSafeMetadata(item.metadata),
            references: item.references.map(persistenceSafeContextReference),
        )
    }

    func persistenceSafeContextAttachment(
        _ attachment: AiChatContextAttachment,
    ) -> AiChatContextAttachment {
        AiChatContextAttachment(
            identifier: attachment.identifier,
            title: attachment.title,
            subtitle: attachment.subtitle,
            kind: attachment.kind,
            metadata: persistenceSafeMetadata(attachment.metadata),
        )
    }

    func requestSummaryAttachmentSnapshot(
        _ snapshot: AiChatAttachmentSnapshot,
    ) -> AiChatAttachmentSnapshot {
        AiChatAttachmentSnapshot(
            id: snapshot.id,
            source: snapshot.source,
            displayTitle: snapshot.displayTitle,
            subtitle: snapshot.subtitle,
            kind: snapshot.kind,
            sourceLocation: snapshot.sourceLocation,
            metadata: snapshot.metadata,
            resolutionResult: strippingFolderStructureTreeMetadata(from: snapshot.resolutionResult),
        )
    }

    func persistenceSafeAttachmentSnapshot(
        _ snapshot: AiChatAttachmentSnapshot,
    ) -> AiChatAttachmentSnapshot {
        AiChatAttachmentSnapshot(
            id: snapshot.id,
            source: snapshot.source,
            displayTitle: snapshot.displayTitle,
            subtitle: snapshot.subtitle,
            kind: snapshot.kind,
            sourceLocation: snapshot.sourceLocation,
            metadata: persistenceSafeMetadata(snapshot.metadata),
            resolutionResult: persistenceSafeResolutionResult(strippingFolderStructureTreeMetadata(from: snapshot
                    .resolutionResult)),
        )
    }

    func persistenceSafeContextPart(
        _ part: AiChatLockedContextPartSnapshot,
    ) -> AiChatLockedContextPartSnapshot {
        AiChatLockedContextPartSnapshot(
            source: part.source,
            resolution: persistenceSafeContextPartResolution(part.resolution),
            canonicalPath: part.canonicalPath,
            displayPath: part.displayPath,
            fileKind: part.fileKind,
            displayTitle: part.displayTitle,
            byteCount: part.byteCount,
            mimeType: part.mimeType,
        )
    }

    func persistenceSafeResolutionResult(
        _ resolution: AiChatAttachmentResolutionResult,
    ) -> AiChatAttachmentResolutionResult {
        switch resolution {
        case let .resolvedText(text, metadata):
            .resolvedText(text: text, metadata: persistenceSafeMetadata(metadata))
        case let .resolvedReference(metadata):
            .resolvedReference(metadata: persistenceSafeMetadata(metadata))
        case let .resolvedPartial(text, truncated, metadata):
            .resolvedPartial(text: text, truncated: truncated, metadata: persistenceSafeMetadata(metadata))
        case let .failure(reason, metadata):
            .failure(reason: reason, metadata: persistenceSafeMetadata(metadata))
        }
    }

    func strippingFolderStructureTreeMetadata(
        from resolution: AiChatAttachmentResolutionResult,
    ) -> AiChatAttachmentResolutionResult {
        switch resolution {
        case let .resolvedText(text, metadata):
            .resolvedText(text: text, metadata: strippingFolderStructureTreeMetadata(from: metadata))
        case let .resolvedReference(metadata):
            .resolvedReference(metadata: strippingFolderStructureTreeMetadata(from: metadata))
        case let .resolvedPartial(text, truncated, metadata):
            .resolvedPartial(
                text: text,
                truncated: truncated,
                metadata: strippingFolderStructureTreeMetadata(from: metadata),
            )
        case let .failure(reason, metadata):
            .failure(reason: reason, metadata: strippingFolderStructureTreeMetadata(from: metadata))
        }
    }

    func strippingFolderStructureTreeMetadata(from metadata: [String: String]) -> [String: String] {
        metadata.filter { key, _ in
            !key.hasPrefix("folderStructure") || key == "folderStructureMode"
        }
    }

    func persistenceSafeContextPartResolution(
        _ resolution: AiChatContextPartResolution,
    ) -> AiChatContextPartResolution {
        switch resolution {
        case let .inlineText(text, metadata):
            .inlineText(text: text, metadata: persistenceSafeMetadata(metadata))
        case let .partialText(text, truncated, metadata):
            .partialText(text: text, truncated: truncated, metadata: persistenceSafeMetadata(metadata))
        case let .referenceOnly(metadata):
            .referenceOnly(metadata: persistenceSafeMetadata(metadata))
        case let .collectionPathList(paths, metadata):
            .collectionPathList(paths: paths, metadata: persistenceSafeMetadata(metadata))
        case let .providerNativeFile(kind, mimeType, metadata):
            .providerNativeFile(kind: kind, mimeType: mimeType, metadata: persistenceSafeMetadata(metadata))
        case let .failure(reason, metadata):
            .failure(reason: reason, metadata: persistenceSafeMetadata(metadata))
        }
    }

    func persistenceSafeMetadata(_ metadata: [String: String]) -> [String: String] {
        metadata.filter { key, _ in
            !["base64Data", "nativeBase64Data", "fileDataBase64"].contains(key)
        }
    }
}
