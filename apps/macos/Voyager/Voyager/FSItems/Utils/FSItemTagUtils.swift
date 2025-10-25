import SwiftUI

struct TagInfo: Equatable {
    let name: String
    let color: Color
    let tag: String
}

enum FSItemTagUtils {
    static func getTagColor(_ tagName: String) -> Color? {
        let lowercasedTag = tagName.lowercased()

        switch lowercasedTag {
        case "red", "빨간색", "빨강":
            return .red
        case "orange", "주황색", "주황":
            return .orange
        case "yellow", "노란색", "노랑":
            return .yellow
        case "green", "초록색", "초록", "녹색":
            return .green
        case "blue", "파란색", "파랑":
            return .blue
        case "purple", "보라색", "보라":
            return .purple
        case "gray", "회색":
            return .gray
        default:
            return nil
        }
    }

    static func getAllTags() -> [TagInfo] {
        [
            TagInfo(name: "빨간색", color: .red, tag: "빨간색"),
            TagInfo(name: "주황색", color: .orange, tag: "주황색"),
            TagInfo(name: "노란색", color: .yellow, tag: "노란색"),
            TagInfo(name: "초록색", color: .green, tag: "초록색"),
            TagInfo(name: "파란색", color: .blue, tag: "파란색"),
            TagInfo(name: "보라색", color: .purple, tag: "보라색"),
            TagInfo(name: "회색", color: .gray, tag: "회색"),
        ]
    }

    static func getTagNames() -> [String] {
        getAllTags().map { $0.name }
    }
}
