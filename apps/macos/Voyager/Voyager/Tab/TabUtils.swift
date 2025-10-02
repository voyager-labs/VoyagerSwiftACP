import Foundation

/// 탭 관련 유틸리티 함수들
enum TabUtils {
    /// 경로를 기반으로 표시 이름 생성
    static func getDisplayName(for path: String) -> String {
        let pathURL = URL(fileURLWithPath: path)

        // 특별한 경로들 처리
        if path == NSHomeDirectory() {
            return "Home"
        } else if path == "/" {
            return "Root"
        } else {
            // 일반적인 경우: 마지막 디렉토리 이름 사용
            return pathURL.lastPathComponent.isEmpty ? "Unknown" : pathURL.lastPathComponent
        }
    }
}
