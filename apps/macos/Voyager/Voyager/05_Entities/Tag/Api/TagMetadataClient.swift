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

    /// 태그를 "name\ncolorCode" 형식으로 저장합니다. 색상 정보를 보존합니다.
    nonisolated static func setTags(_ tags: [Tag], for itemURL: URL) throws {
        if tags.isEmpty {
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

        // "name\ncolorCode" 형식으로 저장
        let rawTags = tags.map { "\($0.name)\n\($0.colorCode)" }
        let tagData = try PropertyListSerialization.data(
            fromPropertyList: rawTags,
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
        // 기존 태그 로드 (colorCode 포함)
        let existingTags = loadTags(from: itemURL) ?? []

        // 태그 토글
        let hasTag = existingTags.contains { $0.name == tagName }
        let updatedTags: [Tag]
        if hasTag {
            // 제거
            updatedTags = existingTags.filter { $0.name != tagName }
        } else {
            // 추가 (기본 색상 0으로)
            let newTag = Tag(name: tagName, colorCode: 0)
            updatedTags = existingTags + [newTag]
        }

        // 색상 보존하여 저장
        try setTags(updatedTags, for: itemURL)
    }
}
