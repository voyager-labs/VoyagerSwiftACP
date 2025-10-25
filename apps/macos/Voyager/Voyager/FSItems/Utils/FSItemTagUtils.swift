import SwiftUI

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
}
