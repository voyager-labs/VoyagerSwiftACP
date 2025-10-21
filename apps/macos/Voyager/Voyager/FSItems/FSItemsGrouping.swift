import Foundation

enum GroupKey: String, Equatable, CaseIterable {
    case none = "None"
    case name = "Name"
    case dateModified = "Date Modified"
    case size = "Size"
    case kind = "Kind"
}

struct GroupedItems: Equatable {
    let groupName: String
    let items: [FSItemModel]

    var count: Int {
        items.count
    }
}

enum FSItemsGrouping {
    private static func groupByName(_ files: [FSItemModel]) -> [GroupedItems] {
        let dictionary = Dictionary(grouping: files) { item -> String in
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

    private static func groupByDate(_ files: [FSItemModel]) -> [GroupedItems] {
        let calendar = Calendar.current
        let now = Date()

        let dateGroups: [(String, (FSItemModel) -> Bool)] = [
            ("Today", { calendar.isDateInToday($0.modifiedDate) }),
            ("Yesterday", { calendar.isDateInYesterday($0.modifiedDate) }),
            ("Previous 7 Days", { item in
                if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) {
                    return item.modifiedDate > weekAgo
                }
                return false
            }),
        ]

        var result: [GroupedItems] = []

        for (groupName, predicate) in dateGroups {
            let items = files.filter(predicate)
            if !items.isEmpty {
                result.append(GroupedItems(groupName: groupName, items: items))
            }
        }

        let remainingFiles = files.filter { item in
            !calendar.isDateInToday(item.modifiedDate) &&
                !calendar.isDateInYesterday(item.modifiedDate) &&
                !(calendar.date(byAdding: .day, value: -7, to: now).map { item.modifiedDate > $0 } ?? false)
        }

        let monthYearGroups = Dictionary(grouping: remainingFiles) { item -> String in
            let itemYear = calendar.component(.year, from: item.modifiedDate)
            let currentYear = calendar.component(.year, from: now)

            if itemYear == currentYear {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMMM"
                return formatter.string(from: item.modifiedDate)
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

    private static func sortMonthYearGroups(_ lhs: GroupedItems, _ rhs: GroupedItems) -> Bool {
        let lhsIsYear = Int(lhs.groupName) != nil
        let rhsIsYear = Int(rhs.groupName) != nil

        if lhsIsYear, rhsIsYear {
            let lhsYear = Int(lhs.groupName) ?? 0
            let rhsYear = Int(rhs.groupName) ?? 0
            return lhsYear > rhsYear
        } else if !lhsIsYear, !rhsIsYear {
            let monthNames = [
                "January", "February", "March", "April", "May", "June",
                "July", "August", "September", "October", "November", "December",
            ]
            let lhsIndex = monthNames.firstIndex(of: lhs.groupName) ?? 0
            let rhsIndex = monthNames.firstIndex(of: rhs.groupName) ?? 0
            return lhsIndex > rhsIndex
        } else {
            return !lhsIsYear
        }
    }

    private static func groupBySize(_ files: [FSItemModel]) -> [GroupedItems] {
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

    private static func groupByKind(_ files: [FSItemModel]) -> [GroupedItems] {
        Dictionary(grouping: files) { $0.kind }
            .map { GroupedItems(groupName: $0.key, items: $0.value) }
            .sorted { $0.groupName < $1.groupName }
    }

    static func groupItems(
        _ items: [FSItemModel],
        by groupKey: GroupKey
    ) -> [GroupedItems] {
        guard groupKey != .none else {
            return [GroupedItems(groupName: "", items: items)]
        }

        var result: [GroupedItems] = []

        switch groupKey {
        case .none:
            break

        case .name:
            result.append(contentsOf: groupByName(items))

        case .dateModified:
            result.append(contentsOf: groupByDate(items))

        case .size:
            let files = items.filter { !$0.isDirectory }
            result.append(contentsOf: groupBySize(files))
            let folders = items.filter { $0.isDirectory }
            if !folders.isEmpty {
                result.append(GroupedItems(groupName: "---", items: folders))
            }

        case .kind:
            let folders = items.filter { $0.isDirectory }
            if !folders.isEmpty {
                result.append(GroupedItems(groupName: "", items: folders))
            }
            let files = items.filter { !$0.isDirectory }
            result.append(contentsOf: groupByKind(files))
        }

        return result
    }
}
