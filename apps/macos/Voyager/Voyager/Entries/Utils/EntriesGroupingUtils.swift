import Foundation
import UniformTypeIdentifiers

enum GroupKey: String, Equatable, CaseIterable {
    case none = "None"
    case name = "Name"
    case kind = "Kind"
    case application = "Application"
    case dateLastOpened = "Date Last Opened"
    case dateAdded = "Date Added"
    case dateModified = "Date Modified"
    case dateCreated = "Date Created"
    case size = "Size"
    case tags = "Tags"
}

struct GroupedItems: Equatable {
    let groupName: String
    let items: [Entry]

    var count: Int {
        items.count
    }
}

// swiftlint:disable type_body_length
enum EntriesGroupingUtils {
    private static func groupByName(_ items: [Entry]) -> [GroupedItems] {
        let dictionary = Dictionary(grouping: items) { item -> String in
            guard let firstChar = item.name.uppercased().first else { return "#" }
            if firstChar.isLetter {
                return String(firstChar)
            } else if firstChar.isNumber {
                return "0-9"
            } else {
                return "#"
            }
        }
        return dictionary
            .map { GroupedItems(groupName: $0.key, items: $0.value) }
            .sorted { lhs, rhs in
                if lhs.groupName == "0-9" { return rhs.groupName == "#" }
                if lhs.groupName == "#" { return false }
                if rhs.groupName == "0-9" || rhs.groupName == "#" { return true }
                return lhs.groupName < rhs.groupName
            }
    }

    private static func groupByDate(
        _ files: [Entry],
        dateKeyPath: KeyPath<Entry, Date> = \.modifiedDate,
    ) -> [GroupedItems] {
        let calendar = Calendar.current
        let now = Date()

        var result: [GroupedItems] = []
        var processedFiles: Set<String> = []

        let recentGroups = groupRecentDateFiles(files, dateKeyPath: dateKeyPath, calendar: calendar, now: now)
        result.append(contentsOf: recentGroups.groups)
        processedFiles.formUnion(recentGroups.processedFiles)

        let remainingFiles = files.filter { !processedFiles.contains($0.id) }

        let monthYearGroups = Dictionary(grouping: remainingFiles) { item -> String in
            let itemYear = calendar.component(.year, from: item[keyPath: dateKeyPath])
            let currentYear = calendar.component(.year, from: now)

            if itemYear == currentYear {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMMM"
                formatter.locale = Locale.current
                return formatter.string(from: item[keyPath: dateKeyPath])
            } else {
                return "\(itemYear)"
            }
        }

        let sortedGroups = monthYearGroups
            .map { GroupedItems(groupName: $0.key, items: $0.value) }
            .sorted(by: sortMonthYearGroups)

        result.append(contentsOf: sortedGroups)

        return result
    }

    private static func groupRecentDateFiles(
        _ files: [Entry],
        dateKeyPath: KeyPath<Entry, Date>,
        calendar: Calendar,
        now: Date,
    ) -> (groups: [GroupedItems], processedFiles: Set<String>) {
        var result: [GroupedItems] = []
        var processedFiles: Set<String> = []

        let todayFiles = files.filter { calendar.isDateInToday($0[keyPath: dateKeyPath]) }
        if !todayFiles.isEmpty {
            result.append(GroupedItems(groupName: "Today", items: todayFiles))
            processedFiles.formUnion(todayFiles.map(\.id))
        }

        let yesterdayFiles = files.filter { calendar.isDateInYesterday($0[keyPath: dateKeyPath]) }
        if !yesterdayFiles.isEmpty {
            result.append(GroupedItems(groupName: "Yesterday", items: yesterdayFiles))
            processedFiles.formUnion(yesterdayFiles.map(\.id))
        }

        let weekAgo = calendar.date(byAdding: .day, value: -8, to: now) ?? now
        let yesterdayEnd = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let weekAgoDate = calendar.startOfDay(for: weekAgo)
        let yesterdayEndDate = calendar.startOfDay(for: yesterdayEnd)

        let previous7DaysFiles = files.filter { item in
            let itemDate = calendar.startOfDay(for: item[keyPath: dateKeyPath])
            return itemDate >= weekAgoDate && itemDate <= yesterdayEndDate && !processedFiles.contains(item.id)
        }
        if !previous7DaysFiles.isEmpty {
            result.append(GroupedItems(groupName: "Previous 7 Days", items: previous7DaysFiles))
            processedFiles.formUnion(previous7DaysFiles.map(\.id))
        }

        let monthAgo = calendar.date(byAdding: .day, value: -37, to: now) ?? now
        let monthAgoDate = calendar.startOfDay(for: monthAgo)

        let previous30DaysFiles = files.filter { item in
            let itemDate = calendar.startOfDay(for: item[keyPath: dateKeyPath])
            return itemDate >= monthAgoDate && itemDate < weekAgoDate && !processedFiles.contains(item.id)
        }
        if !previous30DaysFiles.isEmpty {
            result.append(GroupedItems(groupName: "Previous 30 Days", items: previous30DaysFiles))
            processedFiles.formUnion(previous30DaysFiles.map(\.id))
        }

        return (groups: result, processedFiles: processedFiles)
    }

    private static func sortMonthYearGroups(_ lhs: GroupedItems, _ rhs: GroupedItems) -> Bool {
        let lhsIsYear = Int(lhs.groupName) != nil
        let rhsIsYear = Int(rhs.groupName) != nil

        if lhsIsYear, rhsIsYear {
            let lhsYear = Int(lhs.groupName) ?? 0
            let rhsYear = Int(rhs.groupName) ?? 0
            return lhsYear > rhsYear
        } else if !lhsIsYear, !rhsIsYear {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM"
            formatter.locale = Locale.current

            let calendar = Calendar.current
            let currentYear = calendar.component(.year, from: Date())

            let lhsDate = calendar.date(from: DateComponents(
                year: currentYear,
                month: getMonthNumber(from: lhs.groupName, formatter: formatter),
            )) ?? Date()
            let rhsDate = calendar.date(from: DateComponents(
                year: currentYear,
                month: getMonthNumber(from: rhs.groupName, formatter: formatter),
            )) ?? Date()

            return lhsDate > rhsDate
        } else {
            return !lhsIsYear
        }
    }

    private static func getMonthNumber(from monthName: String, formatter: DateFormatter) -> Int {
        let calendar = Calendar.current
        for month in 1 ... 12 {
            if let date = calendar.date(from: DateComponents(year: 2024, month: month, day: 1)),
               formatter.string(from: date) == monthName
            {
                return month
            }
        }
        return 1
    }

    private static func groupBySize(_ files: [Entry]) -> [GroupedItems] {
        let dictionary = Dictionary(grouping: files) { item -> String in
            let size = item.size
            switch size {
            case 0:
                return "Zero bytes"
            case ..<(1024 * 100):
                return "Less than 100 KB"
            case ..<(1024 * 1024):
                return "100 KB - 1 MB"
            case ..<(1024 * 1024 * 100):
                return "1 MB - 100 MB"
            case ..<(1024 * 1024 * 1024):
                return "100 MB - 1 GB"
            default:
                return "More than 1 GB"
            }
        }

        let sizeOrder = [
            "Zero bytes", "Less than 100 KB", "100 KB - 1 MB",
            "1 MB - 100 MB", "100 MB - 1 GB", "More than 1 GB",
        ]

        return sizeOrder.compactMap { groupName in
            dictionary[groupName].map { GroupedItems(groupName: groupName, items: $0) }
        }
    }

    /// - Parameter entry: 매핑할 Entry
    /// - Returns: 카테고리 이름
    private static func categoryForEntry(_ entry: Entry) -> String {
        if entry.isDirectory {
            return "Folders"
        }

        if entry.fileExtension.lowercased() == "voycoll" {
            return "Collections"
        }

        guard let utType = UTType(filenameExtension: entry.fileExtension.lowercased()) else {
            return "Other"
        }

        return categoryForUTType(utType, fileExtension: entry.fileExtension.lowercased())
    }

    private static func groupByKind(_ files: [Entry]) -> [GroupedItems] {
        Dictionary(grouping: files) { categoryForEntry($0) }
            .map { GroupedItems(groupName: $0.key, items: $0.value) }
            .sorted(by: sortCategoryGroups)
    }

    /// 카테고리 그룹 정렬 순서 (Folders가 맨 위, Other가 마지막, 나머지는 알파벳 순)
    private static func sortCategoryGroups(_ lhs: GroupedItems, _ rhs: GroupedItems) -> Bool {
        if lhs.groupName == "Folders" {
            return true
        }
        if rhs.groupName == "Folders" {
            return false
        }

        if lhs.groupName == "Other" {
            return false
        }
        if rhs.groupName == "Other" {
            return true
        }

        return lhs.groupName < rhs.groupName
    }

    static func groupItems(
        _ items: [Entry],
        by groupKey: GroupKey,
    ) -> [GroupedItems] {
        guard groupKey != .none else {
            return [GroupedItems(groupName: "", items: items)]
        }

        return groupItemsByKey(items, groupKey: groupKey)
    }

    private static func groupItemsByKey(_ items: [Entry], groupKey: GroupKey) -> [GroupedItems] {
        switch groupKey {
        case .none:
            [GroupedItems(groupName: "", items: items)]
        case .name:
            groupItemsByName(items)
        case .kind:
            groupByKind(items)
        case .application:
            groupItemsByApplication(items)
        case .dateLastOpened:
            groupItemsByDateLastOpened(items)
        case .dateAdded:
            groupByDate(items, dateKeyPath: \.addedDate)
        case .dateModified:
            groupByDate(items)
        case .dateCreated:
            groupByDate(items, dateKeyPath: \.createdDate)
        case .size:
            groupItemsBySize(items)
        case .tags:
            groupItemsByTags(items)
        }
    }

    private static func groupItemsByName(_ items: [Entry]) -> [GroupedItems] {
        let sortedItems = items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return [GroupedItems(groupName: "", items: sortedItems)]
    }

    private static func groupItemsByDateLastOpened(_ items: [Entry]) -> [GroupedItems] {
        var result: [GroupedItems] = []
        let itemsWithDates = items.compactMap { item -> Entry? in
            guard item.lastOpenedDate != nil else { return nil }
            return item
        }
        if !itemsWithDates.isEmpty {
            result.append(contentsOf: groupByDate(itemsWithDates, dateKeyPath: \.lastOpenedDate!))
        }

        let itemsWithoutDates = items.filter { $0.lastOpenedDate == nil }
        if !itemsWithoutDates.isEmpty {
            result.append(GroupedItems(groupName: "Earlier", items: itemsWithoutDates))
        }
        return result
    }

    private static func groupItemsByApplication(_ items: [Entry]) -> [GroupedItems] {
        let grouped = Dictionary(grouping: items) { item -> String in
            if item.isDirectory || item.creatorApplication == nil {
                return "Other"
            }
            return item.creatorApplication ?? "Other"
        }

        let sortedGroups = grouped.sorted {
            $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
        }

        var result: [GroupedItems] = []
        for (appName, groupFiles) in sortedGroups {
            let sortedFiles = groupFiles.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            result.append(GroupedItems(groupName: appName, items: sortedFiles))
        }

        return result
    }

    private static func groupItemsBySize(_ items: [Entry]) -> [GroupedItems] {
        var result: [GroupedItems] = []
        let files = items.filter { !$0.isDirectory }
        result.append(contentsOf: groupBySize(files))
        let folders = items.filter(\.isDirectory)
        if !folders.isEmpty {
            result.append(GroupedItems(groupName: "---", items: folders))
        }
        return result
    }

    private static func groupItemsByTags(_ items: [Entry]) -> [GroupedItems] {
        var result: [GroupedItems] = []

        var tagToItems: [String: [Entry]] = [:]
        var itemsWithoutTags: [Entry] = []

        for item in items {
            if let itemTags = item.tags, !itemTags.isEmpty {
                for tag in itemTags {
                    tagToItems[tag.name, default: []].append(item)
                }
            } else {
                itemsWithoutTags.append(item)
            }
        }

        var processedTags = Set<String>()

        for colorCode in EntryTagUtils.colorCodeOrder {
            for (tagName, taggedItems) in tagToItems {
                if let firstTag = taggedItems.first?.tags?.first(where: { $0.name == tagName }),
                   firstTag.colorCode == colorCode
                {
                    result.append(GroupedItems(
                        groupName: tagName,
                        items: taggedItems
                            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
                    ))
                    processedTags.insert(tagName)
                }
            }
        }

        let remainingTags = tagToItems.keys.filter { !processedTags.contains($0) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        for tagName in remainingTags {
            if let taggedItems = tagToItems[tagName] {
                result.append(GroupedItems(
                    groupName: tagName,
                    items: taggedItems.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
                ))
            }
        }

        if !itemsWithoutTags.isEmpty {
            result.append(GroupedItems(
                groupName: "No Tags",
                items: itemsWithoutTags
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
            ))
        }

        return result
    }
}

// MARK: - Category Classification

extension EntriesGroupingUtils {
    private static func categoryForUTType(_ utType: UTType, fileExtension: String) -> String {
        if utType.conforms(to: .application) { return "Applications" }
        if isSpreadsheet(utType: utType, fileExtension: fileExtension) { return "Spreadsheets" }
        if isPresentation(utType: utType, fileExtension: fileExtension) { return "Presentations" }
        if utType.conforms(to: .pdf) { return "PDF Documents" }
        if isMailOrMessage(utType: utType, fileExtension: fileExtension) { return "Mail & Messages" }
        if utType.conforms(to: .image) { return "Images" }
        if isMovie(utType: utType) { return "Movies" }
        if isAudio(utType: utType) { return "Audio" }
        if isArchive(utType: utType) { return "Archives" }
        if isDocument(utType: utType) { return "Documents" }
        return "Other"
    }

    private static func isSpreadsheet(utType: UTType, fileExtension: String) -> Bool {
        utType.identifier.hasPrefix("com.microsoft.excel") ||
            utType.identifier.hasPrefix("org.openxmlformats.spreadsheetml") ||
            utType.identifier == "com.apple.iwork.numbers.numbers" ||
            utType.identifier.hasPrefix("com.apple.iwork.numbers") ||
            fileExtension == "csv"
    }

    private static func isPresentation(utType: UTType, fileExtension: String) -> Bool {
        utType.identifier.hasPrefix("com.microsoft.powerpoint") ||
            utType.identifier.hasPrefix("org.openxmlformats.presentationml") ||
            utType.identifier == "com.apple.iwork.keynote.keynote" ||
            utType.identifier.hasPrefix("com.apple.iwork.keynote") ||
            fileExtension == "key"
    }

    private static func isMailOrMessage(utType: UTType, fileExtension: String) -> Bool {
        utType.identifier.hasPrefix("com.apple.mail") ||
            utType.identifier.hasPrefix("public.vcard") ||
            utType.identifier == "com.apple.mail.emlx" ||
            fileExtension == "eml" ||
            fileExtension == "mbox"
    }

    private static func isMovie(utType: UTType) -> Bool {
        utType.conforms(to: .movie) ||
            utType.conforms(to: .video) ||
            utType.conforms(to: .quickTimeMovie) ||
            utType.conforms(to: .mpeg4Movie) ||
            utType.conforms(to: .avi)
    }

    private static func isAudio(utType: UTType) -> Bool {
        utType.conforms(to: .audio) ||
            utType.conforms(to: .mp3) ||
            utType.identifier.hasPrefix("public.aiff") ||
            utType.identifier == "com.microsoft.waveform-audio"
    }

    private static func isArchive(utType: UTType) -> Bool {
        utType.conforms(to: .archive) ||
            utType.conforms(to: .zip) ||
            utType.conforms(to: .gzip) ||
            utType.conforms(to: .bz2) ||
            utType.identifier == "com.7-zip.7-zip-archive" ||
            utType.identifier == "com.rarlab.rar-archive"
    }

    private static func isDocument(utType: UTType) -> Bool {
        utType.conforms(to: .text) ||
            utType.conforms(to: .rtf) ||
            utType.conforms(to: .plainText) ||
            utType.identifier.hasPrefix("com.microsoft.word")
    }
}

// swiftlint:enable type_body_length
