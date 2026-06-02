import Foundation

struct ContextTransmissionDescriptor {
    let state: String
    let status: String
    let note: String
}

enum ContextPromptTransmission {
    static func descriptor(for resolution: AiChatContextPartResolution)
        -> ContextTransmissionDescriptor
    {
        switch resolution {
        case .inlineText:
            includedTransmissionDescriptor()
        case let .partialText(_, truncated, _):
            partialTextTransmissionDescriptor(truncated: truncated)
        case let .referenceOnly(metadata):
            referenceOnlyTransmissionDescriptor(metadata: metadata)
        case .collectionPathList:
            collectionPathTransmissionDescriptor()
        case let .providerNativeFile(kind, mimeType, _):
            providerNativeTransmissionDescriptor(kind: kind, mimeType: mimeType)
        case let .failure(reason, _):
            failureTransmissionDescriptor(reason: reason)
        }
    }

    private static func includedTransmissionDescriptor() -> ContextTransmissionDescriptor {
        ContextTransmissionDescriptor(
            state: "included",
            status: "Included",
            note: "attachment included as text in provider context",
        )
    }

    private static func partialTextTransmissionDescriptor(truncated: Bool) -> ContextTransmissionDescriptor {
        if truncated {
            return ContextTransmissionDescriptor(
                state: "partial",
                status: "Partial",
                note: "attachment partially included as text in provider context",
            )
        }
        return includedTransmissionDescriptor()
    }

    private static func referenceOnlyTransmissionDescriptor(metadata: [String: String])
        -> ContextTransmissionDescriptor
    {
        if ContextPromptMetadataFormatting.collectionItemPaths(from: metadata).isEmpty {
            return ContextTransmissionDescriptor(
                state: "reference-only",
                status: "Reference only",
                note: "attachment referenced only; contents not included",
            )
        }
        return collectionPathTransmissionDescriptor()
    }

    private static func collectionPathTransmissionDescriptor() -> ContextTransmissionDescriptor {
        ContextTransmissionDescriptor(
            state: "collection-paths",
            status: "Collection paths",
            note: "attachment represented as collection paths only; contents not included",
        )
    }

    private static func providerNativeTransmissionDescriptor(
        kind: AiChatProviderNativeFileKind,
        mimeType: String,
    ) -> ContextTransmissionDescriptor {
        if kind == .codexPathScope {
            return ContextTransmissionDescriptor(
                state: "codex-path",
                status: "Codex path",
                note: "attachment exposed as Codex filesystem path; provider-native transfer not used",
            )
        }
        return ContextTransmissionDescriptor(
            state: "provider-native",
            status: "Uploaded/native",
            note: "provider-native attachment included; uploaded natively as \(mimeType)",
        )
    }

    private static func failureTransmissionDescriptor(reason: AiChatAttachmentResolutionFailure)
        -> ContextTransmissionDescriptor
    {
        if reason == .unsupportedType {
            return ContextTransmissionDescriptor(
                state: "unsupported",
                status: "Unsupported",
                note: "attachment could not be included: unsupported type",
            )
        }
        return ContextTransmissionDescriptor(
            state: "failed",
            status: "Failed",
            note: "attachment could not be included: \(reason.rawValue)",
        )
    }
}

enum ContextPromptMetadataFormatting {
    // prompt에 출력할 metadata는 외부 provider 전송 안전성이 확인된 요약 키만 명시적으로 허용한다.
    private static let promptMetadataAllowedKeys: Set<String> = [
        "collectionItemCount",
        "collectionItemsIncluded",
        "collectionItemsTruncated",
        "encoding",
        "fileExtension",
        "folderStructureMode",
        "mimeType",
        "nativeUploadMode",
        "resolution",
    ]

    static func metadataLines(_ metadata: [String: String], indent: String) -> [String] {
        let filtered = metadata
            .filter { promptMetadataAllowedKeys.contains($0.key) }
            .mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.key.isEmpty && !$0.value.isEmpty }
            .sorted { lhs, rhs in lhs.key < rhs.key }
        guard !filtered.isEmpty else { return [] }
        var lines = ["\(indent)metadata:"]
        lines.append(contentsOf: filtered.map { "\(indent)  \($0.key): \($0.value)" })
        return lines
    }

    static func collectionItemLines(from metadata: [String: String], indent: String) -> [String] {
        let paths = collectionItemPaths(from: metadata)
        guard !paths.isEmpty else { return [] }

        var lines = ["\(indent)collection_items:"]
        lines.append(contentsOf: paths.map { "\(indent)  - \($0)" })
        if metadata["collectionItemsTruncated"]?.lowercased() == "true" {
            lines.append("\(indent)collection_items_truncated: true")
        }
        if let included = normalized(metadata["collectionItemsIncluded"]) {
            lines.append("\(indent)collection_items_included: \(included)")
        }
        if let count = normalized(metadata["collectionItemCount"]) {
            lines.append("\(indent)collection_item_count: \(count)")
        }
        return lines
    }

    static func collectionItemPaths(from metadata: [String: String]) -> [String] {
        guard let rawPaths = metadata["collectionItemPaths"] else { return [] }
        return rawPaths
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func folderStructureLines(from metadata: [String: String], indent: String) -> [String] {
        guard normalized(metadata["folderStructureEntries"]) != nil
            || normalized(metadata["folderStructureDirectoryFilePaths"]) != nil
        else { return [] }

        var lines = ["\(indent)folder_structure:"]
        appendFolderStructureMetadataLines(from: metadata, indent: indent, to: &lines)

        let entries = lineValues(from: metadata["folderStructureEntries"])
        if !entries.isEmpty {
            lines.append("\(indent)  entries:")
            lines.append(contentsOf: entries.map { "\(indent)    - \($0)" })
        }

        let directoryFilePaths = lineValues(from: metadata["folderStructureDirectoryFilePaths"])
        if !directoryFilePaths.isEmpty {
            lines.append("\(indent)  directory_file_paths:")
            lines.append(contentsOf: directoryFilePaths.map { "\(indent)    - \($0)" })
        }
        return lines
    }

    private static func appendFolderStructureMetadataLines(
        from metadata: [String: String],
        indent: String,
        to lines: inout [String],
    ) {
        let keys: [(key: String, label: String)] = [
            ("folderStructureMode", "mode"),
            ("folderStructurePathStyle", "path_style"),
            ("folderStructureRootName", "root_name"),
            ("folderStructureEntriesIncluded", "entries_included"),
            ("folderStructureEntriesTruncated", "entries_truncated"),
            ("folderStructureSkippedCount", "skipped_count"),
            ("folderStructureSymlinkEscapes", "symlink_escapes"),
            ("folderStructureReadFailures", "read_failures"),
        ]
        for item in keys {
            if let value = normalized(metadata[item.key]) {
                lines.append("\(indent)  \(item.label): \(value)")
            }
        }
    }

    private static func lineValues(from value: String?) -> [String] {
        guard let value else { return [] }
        return value
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}
