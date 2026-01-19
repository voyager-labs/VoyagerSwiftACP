import Foundation

enum ConditionPropertyIconUtils {
    private static let keyIconMap: [String: String] = [
        "name": "doc.text",
        "extension": "doc.badge.ellipsis",
        "size": "arrow.up.left.and.arrow.down.right",
        "contentType": "doc.text.magnifyingglass",
        "kind": "tag",
        "isInvisible": "eye.slash",
        "createdAt": "calendar.badge.plus",
        "modifiedAt": "calendar.badge.clock",
        "addedAt": "calendar.badge.plus",
        "lastUsedAt": "clock",
        "contentCreatedAt": "calendar.badge.plus",
        "contentModifiedAt": "calendar.badge.clock",
        "pixelHeight": "rectangle.expand.vertical",
        "pixelWidth": "arrow.left.and.right",
        "colorSpace": "paintpalette",
        "hasAlphaChannel": "circle.lefthalf.filled",
        "duration": "clock",
        "videoBitRate": "waveform.path.ecg",
        "audioBitRate": "waveform.path.ecg",
        "audioSampleRate": "waveform",
        "audioChannelCount": "speaker.wave.2",
        "title": "text.book.closed",
        "numberOfPages": "doc.text",
        "creator": "person",
        "latitude": "location",
        "longitude": "location",
    ]

    static func iconName(for property: SystemProperty) -> String {
        iconName(forKey: property.key, category: property.category)
    }

    static func iconName(forKey key: String, category: String? = nil) -> String {
        if let iconName = keyIconMap[key] {
            return iconName
        }
        if let category {
            return iconName(forCategory: category)
        }
        return "slider.horizontal.3"
    }

    static func iconName(forCategory category: String) -> String {
        switch category {
        case "filesystem": "gearshape"
        case "image": "photo"
        case "video": "video"
        case "audio": "speaker.wave.2"
        case "document": "doc.text"
        case "download": "arrow.down.circle"
        case "content": "square.stack.3d.down.right"
        case "location": "mappin.and.ellipse"
        default: "questionmark.circle"
        }
    }
}
