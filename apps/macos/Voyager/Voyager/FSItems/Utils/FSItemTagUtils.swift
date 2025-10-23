import SwiftUI

enum FSItemTagUtils {
    static func getTagInfo(_ tagName: String) -> (color: Color?, localizedName: String) {
        let currentLanguage = Locale.current.languageCode ?? "en"

        let tagMapping: [String: (Color, [String: String])] = [
            "red": (.red, ["en": "Red", "ko": "빨간색"]),
            "orange": (.orange, ["en": "Orange", "ko": "주황색"]),
            "yellow": (.yellow, ["en": "Yellow", "ko": "노란색"]),
            "green": (.green, ["en": "Green", "ko": "초록색"]),
            "blue": (.blue, ["en": "Blue", "ko": "파란색"]),
            "purple": (.purple, ["en": "Purple", "ko": "보라색"]),
            "gray": (.gray, ["en": "Gray", "ko": "회색"]),

            "빨간색": (.red, ["en": "Red", "ko": "빨간색"]),
            "빨강": (.red, ["en": "Red", "ko": "빨강"]),
            "주황색": (.orange, ["en": "Orange", "ko": "주황색"]),
            "주황": (.orange, ["en": "Orange", "ko": "주황"]),
            "노란색": (.yellow, ["en": "Yellow", "ko": "노란색"]),
            "노랑": (.yellow, ["en": "Yellow", "ko": "노랑"]),
            "초록색": (.green, ["en": "Green", "ko": "초록색"]),
            "초록": (.green, ["en": "Green", "ko": "초록"]),
            "녹색": (.green, ["en": "Green", "ko": "녹색"]),
            "파란색": (.blue, ["en": "Blue", "ko": "파란색"]),
            "파랑": (.blue, ["en": "Blue", "ko": "파랑"]),
            "보라색": (.purple, ["en": "Purple", "ko": "보라색"]),
            "보라": (.purple, ["en": "Purple", "ko": "보라"]),
            "회색": (.gray, ["en": "Gray", "ko": "회색"]),
        ]

        if let (color, translations) = tagMapping[tagName.lowercased()],
           let localizedName = translations[currentLanguage]
        {
            return (color, localizedName)
        }

        return (nil, tagName)
    }
}
