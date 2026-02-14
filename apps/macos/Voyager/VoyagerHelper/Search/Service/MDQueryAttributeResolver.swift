import Foundation

enum MDQueryAttributeResolver {
    private static let derivedAttributeOverrides: [String: String] = [
        "extension": "kMDItemFSName",
        "name_stem": "kMDItemFSName",
        "size": "kMDItemFSSize",
    ]

    private static let nsurlAttributeAliases: [String: String] = [
        "NSURLAddedToDirectoryDateKey": "kMDItemDateAdded",
        "NSURLAttributeModificationDateKey": "kMDItemAttributeChangeDate",
        "NSURLContentAccessDateKey": "kMDItemLastUsedDate",
        "NSURLContentModificationDateKey": "kMDItemContentModificationDate",
        "NSURLContentTypeKey": "kMDItemContentType",
        "NSURLCreationDateKey": "kMDItemFSCreationDate",
        "NSURLFileAllocatedSizeKey": "kMDItemFSSize",
        "NSURLFileSizeKey": "kMDItemFSSize",
        "NSURLHasHiddenExtensionKey": "kMDItemFSIsExtensionHidden",
        "NSURLIsHiddenKey": "kMDItemFSInvisible",
        "NSURLLocalizedNameKey": "kMDItemDisplayName",
        "NSURLNameKey": "kMDItemFSName",
        "NSURLPathKey": "kMDItemPath",
        "NSURLTotalFileAllocatedSizeKey": "kMDItemFSSize",
        "NSURLTotalFileSizeKey": "kMDItemFSSize",
    ]

    static func resolve(propertyKey: String, systemKeys: [String]) -> String? {
        if let override = derivedAttributeOverrides[propertyKey] {
            return override
        }

        var mdimporterCandidate: String?
        var nsurlCandidate: String?

        for rawKey in systemKeys {
            let (prefix, symbol) = parseSystemKey(rawKey)

            if symbol.hasPrefix("kMDItem") {
                if prefix == "mditem" {
                    return symbol
                }
                if prefix == "mdimporter", mdimporterCandidate == nil {
                    mdimporterCandidate = symbol
                    continue
                }
            }

            if prefix == "nsurl",
               let alias = nsurlAttributeAliases[symbol],
               nsurlCandidate == nil
            {
                nsurlCandidate = alias
            }
        }

        return mdimporterCandidate ?? nsurlCandidate
    }

    private static func parseSystemKey(_ key: String) -> (prefix: String, symbol: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separatorIndex = trimmed.firstIndex(of: ":") else {
            return ("", trimmed)
        }

        let prefix = trimmed[..<separatorIndex]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let symbol = trimmed[trimmed.index(after: separatorIndex)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (prefix, symbol)
    }
}
