import Darwin
import Foundation

enum TagMetadataClient {
    enum Error: Swift.Error {
        case failedToRemoveTags
        case failedToSetTags
    }

    private nonisolated static let userTagsXattrName = "com.apple.metadata:_kMDItemUserTags"

    // xattr plist의 "name\ncolorCode" 형식에서 태그 색까지 복원합니다.
    nonisolated static func loadTags(from itemURL: URL) -> [Tag]? {
        guard let rawTags = loadRawUserTags(from: itemURL) else {
            return nil
        }

        let tags = rawTags.compactMap(TagMDItemUserTagParser.parse)
        return tags.isEmpty ? nil : tags
    }

    nonisolated static func loadRawUserTags(from itemURL: URL) -> [String]? {
        guard let tagData = loadUserTagsXattrData(from: itemURL) else {
            return nil
        }

        return try? PropertyListSerialization.propertyList(from: tagData, format: nil) as? [String]
    }

    nonisolated static func loadTagNames(from itemURL: URL) throws -> [String] {
        let values = try itemURL.resourceValues(forKeys: [.tagNamesKey])
        return values.tagNames ?? []
    }

    nonisolated static func setTagNames(_ tagNames: [String], for itemURL: URL) throws {
        if tagNames.isEmpty {
            let result = removexattr(
                itemURL.path,
                userTagsXattrName,
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
            userTagsXattrName,
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
                userTagsXattrName,
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
            userTagsXattrName,
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

    private nonisolated static func loadUserTagsXattrData(from itemURL: URL) -> Data? {
        let size = getxattr(itemURL.path, userTagsXattrName, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0 else {
            return nil
        }

        var data = Data(count: size)
        let result = data.withUnsafeMutableBytes { buffer in
            getxattr(
                itemURL.path,
                userTagsXattrName,
                buffer.baseAddress,
                size,
                0,
                XATTR_NOFOLLOW,
            )
        }
        guard result >= 0 else {
            return nil
        }

        return data
    }
}
