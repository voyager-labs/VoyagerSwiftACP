import Combine
import Foundation

/// 핀된 탭 상태 관리 (UserDefaults 기반)
@MainActor
class PinnedTabsManager: ObservableObject {
    static let shared = PinnedTabsManager()

    private let userDefaults = UserDefaults.standard
    private let pinnedTabsKey = "pinnedTabs"

    // SQLite DATETIME 포맷
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    // UserDefaults 키 상수 (SQLite 스키마와 일치)
    private enum Keys {
        static let id = "id"
        static let targetId = "targetId"
        static let title = "title"
        static let targetType = "targetType"
        static let orderKey = "orderKey"
        static let properties = "properties"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
        static let isArchived = "isArchived"
        static let archivedAt = "archivedAt"
    }

    @Published var pinStateChanged = UUID()

    // 전역 공유 메모리 (모든 탭 정보)
    @Published var allTabs: [UUID: TabModel] = [:]

    private init() {
        // 앱 시작 시 plist에서 핀 탭 로드
        let pinnedTabs = loadFromPlist()
        for tab in pinnedTabs {
            allTabs[tab.id] = tab
        }
    }

    func updateTab(_ tab: TabModel) {
        allTabs[tab.id] = tab
    }

    func removeTab(id: UUID) {
        allTabs.removeValue(forKey: id)
    }

    func notifyPinStateChanged() {
        pinStateChanged = UUID()
    }

    func getPinnedTabs() -> [TabModel] {
        allTabs.values.filter { $0.isPinned }.sorted { $0.title < $1.title }
    }

    func saveToPlist() {
        let pinnedTabs = allTabs.values.filter { $0.isPinned }

        let data = pinnedTabs.enumerated().map { index, tab in
            // properties JSONB 구조
            let properties: [String: Any] = [
                "currentPath": tab.currentPath ?? "",
                "backHistory": tab.backHistory,
                "forwardHistory": tab.forwardHistory,
            ]

            let now = Date()
            let nowString = dateFormatter.string(from: now)
            let recordId = index + 1

            var record: [String: Any] = [
                Keys.id: recordId,
                Keys.targetId: tab.id.uuidString,
                Keys.title: tab.title,
                Keys.targetType: "DIRECTORY",
                Keys.orderKey: index,
                Keys.properties: properties,
                Keys.createdAt: nowString,
                Keys.updatedAt: nowString,
                Keys.isArchived: false,
            ]

            return record
        }

        userDefaults.set(data, forKey: pinnedTabsKey)
    }

    private func loadFromPlist() -> [TabModel] {
        guard let data = userDefaults.array(forKey: pinnedTabsKey) as? [[String: Any]] else {
            return []
        }

        return data.compactMap { dict in
            if let isArchived = dict[Keys.isArchived] as? Bool, isArchived {
                return nil
            }

            guard let targetIdString = dict[Keys.targetId] as? String,
                  let targetId = UUID(uuidString: targetIdString),
                  let title = dict[Keys.title] as? String,
                  let properties = dict[Keys.properties] as? [String: Any]
            else {
                return nil
            }

            let currentPath = (properties["currentPath"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let backHistory = properties["backHistory"] as? [String] ?? []
            let forwardHistory = properties["forwardHistory"] as? [String] ?? []

            return TabModel(
                id: targetId,
                title: title,
                currentPath: currentPath,
                isPinned: true,
                backHistory: backHistory,
                forwardHistory: forwardHistory
            )
        }
    }

    func isTabPinned(id: UUID) -> Bool {
        allTabs[id]?.isPinned ?? false
    }

    func clearPinnedTabs() {
        userDefaults.removeObject(forKey: pinnedTabsKey)
    }
}
