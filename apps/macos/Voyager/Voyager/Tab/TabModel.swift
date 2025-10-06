import Foundation

/// 탭 모델
struct TabModel: Identifiable, Codable {
    let id: UUID
    var title: String
    var currentPath: String?
    var isPinned: Bool
    var navigationHistory: [String]
    var currentHistoryIndex: Int

    init(
        id: UUID = UUID(),
        title: String = "New Tab",
        currentPath: String? = nil,
        isPinned: Bool = false,
        navigationHistory: [String] = [],
        currentHistoryIndex: Int = 0
    ) {
        self.id = id
        self.title = title
        self.currentPath = currentPath
        self.isPinned = isPinned
        self.navigationHistory = navigationHistory
        self.currentHistoryIndex = currentHistoryIndex
    }
}
