import Darwin
import Foundation

enum XattrMetadataReader {
    private static let xattrUserTagsKey = "com.apple.metadata:_kMDItemUserTags"
    private static let xattrFinderCommentKey = "com.apple.metadata:kMDItemFinderComment"

    static func readUserTags(path: String) -> [[Any]] {
        guard let data = readXattr(path: path, key: xattrUserTagsKey) else { return [] }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else {
            return []
        }
        guard let values = plist as? [Any] else { return [] }
        var tags: [[Any]] = []
        tags.reserveCapacity(values.count)
        for value in values {
            let text: String
            if let dataValue = value as? Data {
                text = String(bytes: dataValue, encoding: .utf8) ?? String(describing: dataValue)
            } else {
                text = String(describing: value)
            }
            let parts = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            let name = parts.first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { continue }
            let color = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
            tags.append([name, color])
        }
        return tags
    }

    static func readComment(path: String) -> String? {
        guard let data = readXattr(path: path, key: xattrFinderCommentKey) else { return nil }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else {
            return nil
        }
        if let value = plist as? Data {
            return String(bytes: value, encoding: .utf8) ?? String(describing: value)
        }
        if let value = plist as? String {
            return value
        }
        return String(describing: plist)
    }

    private static func readXattr(path: String, key: String) -> Data? {
        path.withCString { pathPointer in
            key.withCString { keyPointer in
                let size = getxattr(pathPointer, keyPointer, nil, 0, 0, 0)
                guard size > 0 else { return nil }
                var data = Data(count: size)
                let result = data.withUnsafeMutableBytes { buffer in
                    getxattr(pathPointer, keyPointer, buffer.baseAddress, size, 0, 0)
                }
                guard result >= 0 else { return nil }
                return data
            }
        }
    }
}
