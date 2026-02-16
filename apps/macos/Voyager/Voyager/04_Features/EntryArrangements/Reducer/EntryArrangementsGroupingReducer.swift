import ComposableArchitecture
import Foundation

@Reducer
struct EntryArrangementsGroupingReducer {
    typealias State = FileManagerContentState
    typealias Action = EntryArrangementsAction

    @Dependency(\.userDefaultsClient)
    private var userDefaultsClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .setGroupKey(key):
                state.entryArrangements.updateGroupKey(key)
                applyGrouping(state: &state)
                userDefaultsClient.setString(key.rawValue, EntryArrangementsPersistenceKey.groupKey)
                return .none

            case let .toggleCollapsedGroup(groupName):
                if state.entryArrangements.collapsedGroups.contains(groupName) {
                    state.entryArrangements.collapsedGroups.remove(groupName)
                } else {
                    state.entryArrangements.collapsedGroups.insert(groupName)
                }
                return .none

            case .setSortKey, .setSortOrder, .reapply:
                applyGrouping(state: &state)
                return .none
            }
        }
    }

    private func applyGrouping(state: inout State) {
        let arrangements = state.entryArrangements
        if arrangements.groupKey == .none {
            state.entryArrangements.groupedItems = [
                GroupedItems(
                    groupName: "",
                    items: Array(state.entries.displayItems),
                ),
            ]
            return
        }

        state.entryArrangements.groupedItems = groupItems(
            Array(state.entries.displayItems),
            by: arrangements.groupKey,
        )
    }
}

private extension EntryArrangementsGroupingReducer {
    func groupByName(_ items: [Entry]) -> [GroupedItems] {
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

    func groupByDate(
        _ files: [Entry],
        dateKeyPath: KeyPath<Entry, Date> = \.modifiedDate,
    ) -> [GroupedItems] {
        let calendar = Calendar.current
        let now = Date()

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM"
        monthFormatter.locale = Locale.current

        let grouped = Dictionary(grouping: files) { item in
            DateGroupBucket.bucket(for: item[keyPath: dateKeyPath], now: now, calendar: calendar)
        }

        return grouped.keys.sorted(by: DateGroupBucket.ordered).compactMap { bucket in
            guard let groupedItems = grouped[bucket] else {
                return nil
            }
            return GroupedItems(
                groupName: dateGroupName(
                    for: bucket,
                    now: now,
                    calendar: calendar,
                    monthFormatter: monthFormatter,
                ),
                items: groupedItems,
            )
        }
    }

    func dateGroupName(
        for bucket: DateGroupBucket,
        now: Date,
        calendar: Calendar,
        monthFormatter: DateFormatter,
    ) -> String {
        switch bucket {
        case .today:
            return "Today"
        case .yesterday:
            return "Yesterday"
        case .previous7Days:
            return "Previous 7 Days"
        case .previous30Days:
            return "Previous 30 Days"
        case let .month(month):
            let currentYear = calendar.component(.year, from: now)
            guard let date = calendar.date(from: DateComponents(year: currentYear, month: month, day: 1)) else {
                return "\(month)"
            }
            return monthFormatter.string(from: date)
        case let .year(year):
            return "\(year)"
        }
    }

    private nonisolated(unsafe) static let sizeRangeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = false
        return formatter
    }()

    private static func formatByteCount(_ byteCount: Int64) -> String {
        sizeRangeFormatter.string(fromByteCount: byteCount)
    }

    func sizeGroupName(for bucket: ByteSizeBucket) -> String {
        switch bucket {
        case .zeroBytes:
            "Zero bytes"
        case .lessThanHundredKB:
            "Less than \(Self.formatByteCount(ByteSizeBucket.hundredKB))"
        case .hundredKBToOneMB:
            "\(Self.formatByteCount(ByteSizeBucket.hundredKB)) - \(Self.formatByteCount(ByteSizeBucket.oneMB))"
        case .oneMBToHundredMB:
            "\(Self.formatByteCount(ByteSizeBucket.oneMB)) - \(Self.formatByteCount(ByteSizeBucket.hundredMB))"
        case .hundredMBToOneGB:
            "\(Self.formatByteCount(ByteSizeBucket.hundredMB)) - \(Self.formatByteCount(ByteSizeBucket.oneGB))"
        case .moreThanOneGB:
            "More than \(Self.formatByteCount(ByteSizeBucket.oneGB))"
        }
    }

    func groupBySize(_ files: [Entry]) -> [GroupedItems] {
        let dictionary = Dictionary(grouping: files) { item in
            ByteSizeBucket.bucket(for: item.size)
        }

        return ByteSizeBucket.allCases.compactMap { bucket in
            dictionary[bucket].map { GroupedItems(groupName: sizeGroupName(for: bucket), items: $0) }
        }
    }

    func categoryForEntry(_ entry: Entry) -> String {
        if entry.isDirectory {
            return "Folders"
        }

        if entry.fileExtension.lowercased() == CollectionConstants.fileExtension {
            return "Collections"
        }

        let normalizedKind = entry.kind.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedKind.isEmpty ? "Other" : normalizedKind
    }

    func groupByKind(_ files: [Entry]) -> [GroupedItems] {
        Dictionary(grouping: files) { categoryForEntry($0) }
            .map { GroupedItems(groupName: $0.key, items: $0.value) }
            .sorted(by: sortCategoryGroups)
    }

    func sortCategoryGroups(_ lhs: GroupedItems, _ rhs: GroupedItems) -> Bool {
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

    func groupItems(
        _ items: [Entry],
        by groupKey: GroupKey,
    ) -> [GroupedItems] {
        guard groupKey != .none else {
            return [GroupedItems(groupName: "", items: items)]
        }

        return groupItemsByKey(items, groupKey: groupKey)
    }

    func groupItemsByKey(_ items: [Entry], groupKey: GroupKey) -> [GroupedItems] {
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

    func groupItemsByName(_ items: [Entry]) -> [GroupedItems] {
        let sortedItems = items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return [GroupedItems(groupName: "", items: sortedItems)]
    }

    func groupItemsByDateLastOpened(_ items: [Entry]) -> [GroupedItems] {
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

    func groupItemsByApplication(_ items: [Entry]) -> [GroupedItems] {
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

    func groupItemsBySize(_ items: [Entry]) -> [GroupedItems] {
        var result: [GroupedItems] = []
        let files = items.filter { !$0.isDirectory }
        result.append(contentsOf: groupBySize(files))
        let folders = items.filter(\.isDirectory)
        if !folders.isEmpty {
            result.append(GroupedItems(groupName: "---", items: folders))
        }
        return result
    }

    func groupItemsByTags(_ items: [Entry]) -> [GroupedItems] {
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

        for tagColor in TagColor.colorOrder {
            for (tagName, taggedItems) in tagToItems {
                if let firstTag = taggedItems.first?.tags?.first(where: { $0.name == tagName }),
                   firstTag.tagColor == tagColor
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
