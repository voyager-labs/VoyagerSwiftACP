import Foundation

/// 탭 모델
struct TabModel: Identifiable, Codable {
    let id: UUID
    var title: String
    var currentPath: String?
    var isPinned: Bool
    var backHistory: [String]
    var forwardHistory: [String]
    init(
        id: UUID = UUID(),
        title: String = "New Tab",
        currentPath: String? = nil,
        isPinned: Bool = false,
        backHistory: [String] = [],
        forwardHistory: [String] = []
    ) {
        self.id = id
        self.title = title
        self.currentPath = currentPath
        self.isPinned = isPinned
        self.backHistory = backHistory
        self.forwardHistory = forwardHistory
    }
}
