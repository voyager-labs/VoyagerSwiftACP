import Foundation

/// 탭 모델
struct TabModel: Identifiable {
    let id: UUID
    var title: String
    var currentPath: String?
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        title: String = "New Tab",
        currentPath: String? = nil,
        isPinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.currentPath = currentPath
        self.isPinned = isPinned
    }
}
