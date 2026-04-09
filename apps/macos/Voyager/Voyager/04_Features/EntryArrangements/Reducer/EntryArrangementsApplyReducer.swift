import ComposableArchitecture
import Foundation

import VoyagerEntitiesEntry

@Reducer
struct EntryArrangementsApplyReducer {
    typealias State = EntryArrangementsState
    typealias Action = EntryArrangementsAction

    @Dependency(\.date)
    private var date

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .apply(items: items, isCollectionMode: isCollectionMode):
                let sortedItems = sortItems(
                    items,
                    by: state.sortKey,
                    order: state.sortOrder,
                )

                let groupedItems = groupItems(
                    sortedItems,
                    by: state.groupKey,
                    now: date(),
                )
                state.groupedItems = groupedItems

                return .send(.delegate(.applied(
                    sortedItems: sortedItems,
                    isCollectionMode: isCollectionMode,
                )))

            case .setSortKey,
                 .setSortOrder,
                 .setGroupKey,
                 .toggleCollapsedGroup,
                 .reapply,
                 .delegate:
                return .none
            }
        }
    }

    private func sortItems(
        _ items: [EntryModel],
        by sortKey: SortKey,
        order: SortOrder,
    ) -> [EntryModel] {
        items.sorted { item1, item2 in
            let comparison = compareItems(item1, item2, by: sortKey)
            return order == .ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }

    private func compareItems(_ item1: EntryModel, _ item2: EntryModel, by sortKey: SortKey) -> ComparisonResult {
        switch sortKey {
        case .name:
            return item1.name.localizedCaseInsensitiveCompare(item2.name)
        case .kind:
            return item1.facets.kind.localizedCaseInsensitiveCompare(item2.facets.kind)
        case .application:
            let app1 = item1.facets.creatorApplication ?? ""
            let app2 = item2.facets.creatorApplication ?? ""
            return app1.localizedCaseInsensitiveCompare(app2)
        case .dateLastOpened:
            return compareDates(
                item1.facets.lastOpenedDate ?? .distantPast,
                item2.facets.lastOpenedDate ?? .distantPast,
            )
        case .dateAdded:
            return compareDates(item1.facets.addedDate, item2.facets.addedDate)
        case .dateModified:
            return compareDates(item1.modifiedDate, item2.modifiedDate)
        case .dateCreated:
            return compareDates(item1.facets.createdDate, item2.facets.createdDate)
        case .size:
            return compareSizes(item1.size, item2.size)
        case .tags:
            let tag1Name = item1.facets.tags?.first?.name ?? ""
            let tag2Name = item2.facets.tags?.first?.name ?? ""
            return tag1Name.localizedCaseInsensitiveCompare(tag2Name)
        }
    }

    private func compareDates(_ date1: Date, _ date2: Date) -> ComparisonResult {
        if date1 < date2 { return .orderedAscending }
        if date1 > date2 { return .orderedDescending }
        return .orderedSame
    }

    private func compareSizes(_ size1: Int64, _ size2: Int64) -> ComparisonResult {
        if size1 < size2 { return .orderedAscending }
        if size1 > size2 { return .orderedDescending }
        return .orderedSame
    }
}

private extension EntryArrangementsApplyReducer {
    func groupItems(
        _ items: [EntryModel],
        by groupKey: GroupKey,
        now: Date,
    ) -> [GroupedItems] {
        guard groupKey != .none else {
            return [GroupedItems(groupName: "", items: items)]
        }

        return groupItemsByKey(items, groupKey: groupKey, now: now)
    }

    func resolveTagColorCode(tagName: String, items: [EntryModel]) -> Int? {
        let candidateCodes = items
            .compactMap { item in
                item.facets.tags?.first(where: { $0.name == tagName })?.colorCode
            }

        guard !candidateCodes.isEmpty else { return nil }

        for tagColor in TagColor.colorOrder {
            if let matchedCode = candidateCodes.first(where: { TagColor(colorCode: $0) == tagColor }) {
                return matchedCode
            }
        }

        return candidateCodes.min()
    }

    func groupItemsByKey(
        _ items: [EntryModel],
        groupKey: GroupKey,
        now: Date,
    ) -> [GroupedItems] {
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
            groupItemsByDateLastOpened(items, now: now)
        case .dateAdded:
            groupByDate(items, dateProvider: { $0.facets.addedDate }, now: now)
        case .dateModified:
            groupByDate(items, now: now)
        case .dateCreated:
            groupByDate(items, dateProvider: { $0.facets.createdDate }, now: now)
        case .size:
            groupItemsBySize(items)
        case .tags:
            groupItemsByTags(items)
        }
    }

    func groupItemsByName(_ items: [EntryModel]) -> [GroupedItems] {
        let sortedItems = items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return [GroupedItems(groupName: "", items: sortedItems)]
    }

    func groupItemsByDateLastOpened(_ items: [EntryModel], now: Date) -> [GroupedItems] {
        var result: [GroupedItems] = []
        let itemsWithDates = items.compactMap { item -> EntryModel? in
            guard item.facets.lastOpenedDate != nil else { return nil }
            return item
        }
        if !itemsWithDates.isEmpty {
            result.append(contentsOf: groupByDate(
                itemsWithDates,
                dateProvider: { $0.facets.lastOpenedDate ?? .distantPast },
                now: now,
            ))
        }

        let itemsWithoutDates = items.filter { $0.facets.lastOpenedDate == nil }
        if !itemsWithoutDates.isEmpty {
            result.append(GroupedItems(groupName: "Earlier", items: itemsWithoutDates))
        }
        return result
    }

    func groupByDate(
        _ files: [EntryModel],
        dateProvider: (EntryModel) -> Date = { $0.modifiedDate },
        now: Date,
    ) -> [GroupedItems] {
        let calendar = Calendar.current

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM"
        monthFormatter.locale = Locale.current

        let grouped = Dictionary(grouping: files) { item in
            DateGroupBucket.bucket(for: dateProvider(item), now: now, calendar: calendar)
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

    func groupBySize(_ files: [EntryModel]) -> [GroupedItems] {
        let dictionary = Dictionary(grouping: files) { item in
            ByteSizeBucket.bucket(for: item.size)
        }

        return ByteSizeBucket.allCases.compactMap { bucket in
            dictionary[bucket].map { GroupedItems(groupName: sizeGroupName(for: bucket), items: $0) }
        }
    }

    func groupItemsBySize(_ items: [EntryModel]) -> [GroupedItems] {
        var result: [GroupedItems] = []
        let files = items.filter { !$0.isFolder }
        result.append(contentsOf: groupBySize(files))
        let folders = items.filter(\.isFolder)
        if !folders.isEmpty {
            result.append(GroupedItems(groupName: "---", items: folders))
        }
        return result
    }

    func categoryForEntry(_ entry: EntryModel) -> String {
        if entry.isFolder {
            return "Folders"
        }

        if entry.fileExtension.lowercased() == CollectionConstants.fileExtension {
            return "Collections"
        }

        let normalizedKind = entry.facets.kind.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedKind.isEmpty ? "Other" : normalizedKind
    }

    func groupByKind(_ files: [EntryModel]) -> [GroupedItems] {
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

    func groupItemsByApplication(_ items: [EntryModel]) -> [GroupedItems] {
        let grouped = Dictionary(grouping: items) { item -> String in
            if item.isFolder || item.facets.creatorApplication == nil {
                return "Other"
            }
            return item.facets.creatorApplication ?? "Other"
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

    func groupItemsByTags(_ items: [EntryModel]) -> [GroupedItems] {
        var result: [GroupedItems] = []

        var tagToItems: [String: [EntryModel]] = [:]
        var itemsWithoutTags: [EntryModel] = []

        for item in items {
            if let itemTags = item.facets.tags, !itemTags.isEmpty {
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
                if let resolvedColorCode = resolveTagColorCode(tagName: tagName, items: taggedItems),
                   TagColor(colorCode: resolvedColorCode) == tagColor
                {
                    result.append(GroupedItems(
                        groupName: tagName,
                        items: taggedItems
                            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
                        colorCode: resolvedColorCode,
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
                    colorCode: resolveTagColorCode(tagName: tagName, items: taggedItems),
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
