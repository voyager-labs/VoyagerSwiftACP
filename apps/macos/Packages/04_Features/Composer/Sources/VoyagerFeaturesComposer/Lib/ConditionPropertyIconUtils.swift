import Foundation

enum ConditionPropertyIconUtils {
    private static let keyIconMap: [String: String] = [
        "name": "doc.text",
        "size": "arrow.up.left.and.arrow.down.right",
        "content_type": "doc.text.magnifyingglass",
        "kind": "tag",
        "is_hidden": "eye.slash",
        "creation_date": "calendar.badge.plus",
        "content_modification_date": "calendar.badge.clock",
        "date_added": "calendar.badge.plus",
        "last_used_date": "clock",
        "content_creation_date": "calendar.badge.plus",
        "pixel_height": "rectangle.expand.vertical",
        "pixel_width": "arrow.left.and.right",
        "color_space": "paintpalette",
        "has_alpha_channel": "circle.lefthalf.filled",
        "duration_seconds": "clock",
        "video_bit_rate": "waveform.path.ecg",
        "audio_bit_rate": "waveform.path.ecg",
        "audio_sample_rate": "waveform",
        "audio_channel_count": "speaker.wave.2",
        "title": "text.book.closed",
        "number_of_pages": "doc.text",
        "creator": "person",
        "latitude": "location",
        "longitude": "location",
    ]

    static func iconName(forKey key: String, category: String? = nil, type: String? = nil) -> String {
        if let iconName = keyIconMap[key] {
            return iconName
        }
        if let category {
            if category == "misc", let type {
                return iconName(forType: type)
            }
            return iconName(forCategory: category)
        }
        return "slider.horizontal.3"
    }

    static func iconName(forCategory category: String) -> String {
        switch category {
        case "common": "list.bullet.rectangle"
        case "date": "calendar"
        case "filesystem": "folder"
        case "image": "photo"
        case "video": "video"
        case "audio": "speaker.wave.2"
        case "storage": "externaldrive"
        case "misc": "questionmark.circle"
        default: "questionmark.circle"
        }
    }

    static func iconName(forType type: String) -> String {
        switch type {
        case "date": "calendar"
        case "number": "number"
        case "boolean": "checkmark.circle"
        case "string": "textformat"
        case "string_list": "tag"
        case "categorical": "tag"
        default: "slider.horizontal.3"
        }
    }
}
