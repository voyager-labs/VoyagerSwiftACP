import CoreServices
import Darwin
import Foundation

enum TagMetadataClient {
    enum Error: Swift.Error {
        case failedToRemoveTags
        case failedToSetTags
    }

    // MDItem의 kMDItemUserTags 형식("name\ncolorCode")에서 태그 색까지 복원합니다.
    nonisolated static func loadTags(from itemURL: URL) -> [Tag]? {
        guard let mdItem = MDItemCreate(kCFAllocatorDefault, itemURL.path as CFString),
              let rawTags = MDItemCopyAttribute(mdItem, "kMDItemUserTags" as CFString) as? [String]
        else {
            return nil
        }

        let tags = rawTags.compactMap(TagMDItemUserTagParser.parse)
        return tags.isEmpty ? nil : tags
    }

    nonisolated static func loadTagNames(from itemURL: URL) throws -> [String] {
        let values = try itemURL.resourceValues(forKeys: [.tagNamesKey])
        return values.tagNames ?? []
    }

    nonisolated static func setTagNames(_ tagNames: [String], for itemURL: URL) throws {
        if tagNames.isEmpty {
            let result = removexattr(
                itemURL.path,
                "com.apple.metadata:_kMDItemUserTags",
                XATTR_NOFOLLOW,
            )
            if result != 0, errno != ENOATTR {
                throw Error.failedToRemoveTags
            }
            return
        }

        let tagData = try PropertyListSerialization.data(
            fromPropertyList: tagNames,
            format: .binary,
            options: 0,
        )

        let result = setxattr(
            itemURL.path,
            "com.apple.metadata:_kMDItemUserTags",
            (tagData as NSData).bytes,
            tagData.count,
            0,
            XATTR_NOFOLLOW,
        )
        if result != 0 {
            throw Error.failedToSetTags
        }
    }

    nonisolated static func toggleTag(_ tagName: String, for itemURL: URL) throws {
        var currentTags = try loadTagNames(from: itemURL)

        if currentTags.contains(tagName) {
            currentTags.removeAll { $0 == tagName }
        } else {
            currentTags.append(tagName)
        }

        try setTagNames(currentTags, for: itemURL)
    }
}
