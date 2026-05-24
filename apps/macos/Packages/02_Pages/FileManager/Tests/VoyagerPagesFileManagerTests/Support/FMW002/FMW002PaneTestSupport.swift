import Foundation

// FMW-002 패인 관리 테스트 서포트
// FileManagerSidebarPreferenceReducer의 클램프 상수와 동기화

enum FMW002PaneTestSupport {
    enum SidebarWidth {
        static let min: CGFloat = 150
        static let max: CGFloat = 400
        static let defaultValue: CGFloat = 220
        static let inRange: CGFloat = 250
        static let belowMinimum: CGFloat = 100
        static let aboveMaximum: CGFloat = 500
    }
}
