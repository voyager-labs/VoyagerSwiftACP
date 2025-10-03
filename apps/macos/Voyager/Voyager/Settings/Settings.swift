import Combine
import Foundation

/// 전역 설정 관리자
@MainActor
class Settings: ObservableObject {
    static let shared = Settings()

    @Published var defaultTabPath: String

    private let userDefaults = UserDefaults.standard
    private let defaultTabPathKey = "defaultTabPath"

    private init() {
        // 기본 경로 설정 (홈 디렉토리)
        defaultTabPath = userDefaults.string(forKey: defaultTabPathKey) ?? NSHomeDirectory()
    }

    /// 기본 탭 경로 업데이트
    func updateDefaultTabPath(_ path: String) {
        defaultTabPath = path
        userDefaults.set(path, forKey: defaultTabPathKey)
    }

    /// 기본 탭 경로 리셋 (홈 디렉토리로)
    func resetDefaultTabPath() {
        updateDefaultTabPath(NSHomeDirectory())
    }

    /// 경로가 유효한지 확인
    func isValidPath(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
