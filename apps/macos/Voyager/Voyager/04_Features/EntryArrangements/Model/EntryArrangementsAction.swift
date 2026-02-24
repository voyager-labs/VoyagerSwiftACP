import Foundation

#if canImport(ComposableArchitecture)
import ComposableArchitecture

@CasePathable
enum EntryArrangementsAction: CasePathable, Equatable, Sendable {
    case setSortKey(SortKey)
    case setSortOrder(SortOrder)
    case setGroupKey(GroupKey)
    case toggleCollapsedGroup(String)
    case reapply

    case delegate(EntryArrangementsDelegate)
    case apply(items: [EntryModel], isCollectionMode: Bool)
}

@CasePathable
enum EntryArrangementsDelegate: CasePathable, Equatable, Sendable {
    case requestApply
    case applied(sortedItems: [EntryModel], isCollectionMode: Bool)
}

#else

enum EntryArrangementsAction: Equatable, Sendable {}

enum EntryArrangementsDelegate: Equatable, Sendable {}

#endif
