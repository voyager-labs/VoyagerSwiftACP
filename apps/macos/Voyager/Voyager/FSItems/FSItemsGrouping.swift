import Foundation

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
    let items: [FSItem]

    var count: Int {
        items.count
    }
}

enum FSItemsGrouping {
    private static func groupByName(_ items: [FSItem]) -> [GroupedItems] {
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
        _ files: [FSItem],
        dateKeyPath: KeyPath<FSItem, Date> = \.modifiedDate
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
        _ files: [FSItem],
        dateKeyPath: KeyPath<FSItem, Date>,
        calendar: Calendar,
        now: Date
    ) -> (groups: [GroupedItems], processedFiles: Set<String>) {
        var result: [GroupedItems] = []
        var processedFiles: Set<String> = []

        let todayFiles = files.filter { calendar.isDateInToday($0[keyPath: dateKeyPath]) }
        if !todayFiles.isEmpty {
            result.append(GroupedItems(groupName: "Today", items: todayFiles))
            processedFiles.formUnion(todayFiles.map { $0.id })
        }

        let yesterdayFiles = files.filter { calendar.isDateInYesterday($0[keyPath: dateKeyPath]) }
        if !yesterdayFiles.isEmpty {
            result.append(GroupedItems(groupName: "Yesterday", items: yesterdayFiles))
            processedFiles.formUnion(yesterdayFiles.map { $0.id })
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
            processedFiles.formUnion(previous7DaysFiles.map { $0.id })
        }

        let monthAgo = calendar.date(byAdding: .day, value: -37, to: now) ?? now
        let monthAgoDate = calendar.startOfDay(for: monthAgo)

        let previous30DaysFiles = files.filter { item in
            let itemDate = calendar.startOfDay(for: item[keyPath: dateKeyPath])
            return itemDate >= monthAgoDate && itemDate < weekAgoDate && !processedFiles.contains(item.id)
        }
        if !previous30DaysFiles.isEmpty {
            result.append(GroupedItems(groupName: "Previous 30 Days", items: previous30DaysFiles))
            processedFiles.formUnion(previous30DaysFiles.map { $0.id })
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
                month: getMonthNumber(from: lhs.groupName, formatter: formatter)
            )) ?? Date()
            let rhsDate = calendar.date(from: DateComponents(
                year: currentYear,
                month: getMonthNumber(from: rhs.groupName, formatter: formatter)
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

    private static func groupBySize(_ files: [FSItem]) -> [GroupedItems] {
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

    private static func groupByKind(_ files: [FSItem]) -> [GroupedItems] {
        Dictionary(grouping: files) { $0.kind }
            .map { GroupedItems(groupName: $0.key, items: $0.value) }
            .sorted { $0.groupName < $1.groupName }
    }

    static func groupItems(
        _ items: [FSItem],
        by groupKey: GroupKey
    ) -> [GroupedItems] {
        guard groupKey != .none else {
            return [GroupedItems(groupName: "", items: items)]
        }

        return groupItemsByKey(items, groupKey: groupKey)
    }

    private static func groupItemsByKey(_ items: [FSItem], groupKey: GroupKey) -> [GroupedItems] {
        switch groupKey {
        case .none:
            return [GroupedItems(groupName: "", items: items)]
        case .name:
            return groupItemsByName(items)
        case .kind:
            return groupItemsByKind(items)
        case .application:
            return groupItemsByApplication(items)
        case .dateLastOpened:
            return groupItemsByDateLastOpened(items)
        case .dateAdded:
            return groupByDate(items, dateKeyPath: \.addedDate)
        case .dateModified:
            return groupByDate(items)
        case .dateCreated:
            return groupByDate(items, dateKeyPath: \.createdDate)
        case .size:
            return groupItemsBySize(items)
        case .tags:
            return groupItemsByTags(items)
        }
    }

    private static func groupItemsByName(_ items: [FSItem]) -> [GroupedItems] {
        let sortedItems = items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return [GroupedItems(groupName: "", items: sortedItems)]
    }

    private static func groupItemsByKind(_ items: [FSItem]) -> [GroupedItems] {
        var result: [GroupedItems] = []
        let folders = items.filter { $0.isDirectory }
        if !folders.isEmpty {
            result.append(GroupedItems(groupName: "", items: folders))
        }
        let files = items.filter { !$0.isDirectory }
        result.append(contentsOf: groupByKind(files))
        return result
    }

    private static func groupItemsByDateLastOpened(_ items: [FSItem]) -> [GroupedItems] {
        var result: [GroupedItems] = []
        let itemsWithDates = items.compactMap { item -> FSItem? in
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

    private static func groupItemsByApplication(_ items: [FSItem]) -> [GroupedItems] {
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

    private static func groupItemsBySize(_ items: [FSItem]) -> [GroupedItems] {
        var result: [GroupedItems] = []
        let files = items.filter { !$0.isDirectory }
        result.append(contentsOf: groupBySize(files))
        let folders = items.filter { $0.isDirectory }
        if !folders.isEmpty {
            result.append(GroupedItems(groupName: "---", items: folders))
        }
        return result
    }

    private static func groupItemsByTags(_ items: [FSItem]) -> [GroupedItems] {
        var result: [GroupedItems] = []

        var tagToItems: [String: [FSItem]] = [:]
        var itemsWithoutTags: [FSItem] = []

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

        for colorCode in FSItemTagUtils.colorCodeOrder {
            for (tagName, taggedItems) in tagToItems {
                if let firstTag = taggedItems.first?.tags?.first(where: { $0.name == tagName }),
                   firstTag.colorCode == colorCode
                {
                result.append(GroupedItems(
                        groupName: tagName,
                        items: taggedItems
                            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
                    items: taggedItems.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                ))
            }
        }

        if !itemsWithoutTags.isEmpty {
            result.append(GroupedItems(
                groupName: "No Tags",
                items: itemsWithoutTags.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            ))
        }

        return result
    }
}
