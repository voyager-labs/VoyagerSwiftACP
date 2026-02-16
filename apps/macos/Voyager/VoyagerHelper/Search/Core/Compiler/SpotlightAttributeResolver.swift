import Foundation

enum SpotlightAttributeResolver {
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
            let parsed = SystemKeyParser.parse(rawKey)
            let prefix = parsed.prefix
            let symbol = parsed.symbol

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
}
