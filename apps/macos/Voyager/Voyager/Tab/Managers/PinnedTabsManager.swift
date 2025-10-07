import Combine
import Foundation

/// 핀된 탭 상태 관리 (UserDefaults 기반)
@MainActor
class PinnedTabsManager: ObservableObject {
    static let shared = PinnedTabsManager()

    private let userDefaults = UserDefaults.standard
    private let pinnedTabsKey = "pinnedTabs"

    // UserDefaults 키 상수
    private enum Keys {
        static let id = "id"
        static let title = "title"
        static let currentPath = "currentPath"
        static let backHistory = "backHistory"
        static let forwardHistory = "forwardHistory"
        static let pinnedAt = "pinnedAt"
    }

    @Published var pinStateChanged = UUID()

    private init() {}

    func savePinnedTabs(_ tabs: [TabModel]) {
        let pinnedTabs = tabs.filter { $0.isPinned }
        let data = pinnedTabs.map { tab in
            [
                Keys.id: tab.id.uuidString,
                Keys.title: tab.title,
                Keys.currentPath: tab.currentPath ?? "",
                Keys.backHistory: tab.backHistory,
                Keys.forwardHistory: tab.forwardHistory,
                Keys.pinnedAt: Date().timeIntervalSince1970,
            ]
        }

        userDefaults.set(data, forKey: pinnedTabsKey)

        pinStateChanged = UUID()
    }

    func loadPinnedTabs() -> [TabModel] {
        guard let data = userDefaults.array(forKey: pinnedTabsKey) as? [[String: Any]] else {
            return []
        }

        return data.compactMap { dict in
            guard let idString = dict[Keys.id] as? String,
                  let id = UUID(uuidString: idString),
                  let title = dict[Keys.title] as? String
            else {
                return nil
            }

            let currentPath = (dict[Keys.currentPath] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let backHistory = dict[Keys.backHistory] as? [String] ?? []
            let forwardHistory = dict[Keys.forwardHistory] as? [String] ?? []

            return TabModel(
                id: id,
                title: title,
                currentPath: currentPath,
                isPinned: true,
                backHistory: backHistory,
                forwardHistory: forwardHistory
            )
        }
    }

    func isTabPinned(id: UUID) -> Bool {
        let pinnedTabs = loadPinnedTabs()
        return pinnedTabs.contains { $0.id == id }
    }

    func clearPinnedTabs() {
        userDefaults.removeObject(forKey: pinnedTabsKey)
    }
}
