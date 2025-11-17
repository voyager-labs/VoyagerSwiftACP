import SwiftUI

enum FSItemTagUtils {
    static let colorCodeOrder = [6, 7, 5, 2, 4, 3, 1]

    static func getTagColor(colorCode: Int) -> Color {
        switch colorCode {
        case 1: return .gray
        case 2: return .green
        case 3: return .purple
        case 4: return .blue
        case 5: return .yellow
        case 6: return .red
        case 7: return .orange
        default: return .gray
        }
    }

    nonisolated static func getFavoriteTagNames() -> [String] {
        guard let finderDefaults = UserDefaults(suiteName: "com.apple.finder"),
              let tagNames = finderDefaults.array(forKey: "FavoriteTagNames") as? [String]
        else {
            return []
        }
        return tagNames
    }

    nonisolated static func getTagNameToColorCodeMapping() -> [String: Int] {
        let indexToColorCode = [0: 0, 1: 6, 2: 7, 3: 5, 4: 2, 5: 4, 6: 3, 7: 1]
        let tagNames = getFavoriteTagNames()
        return Dictionary(uniqueKeysWithValues: tagNames.enumerated().map { index, name in
            (name, indexToColorCode[index] ?? 0)
        })
    }
}
