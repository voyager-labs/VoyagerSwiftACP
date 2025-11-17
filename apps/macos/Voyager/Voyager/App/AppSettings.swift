import Combine
import Foundation

/// 전역 설정 관리자
@MainActor
class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var defaultTabPath: String

    private let userDefaults = UserDefaults.standard
    private let defaultTabPathKey = "defaultTabPath"

    private init() {
        defaultTabPath = userDefaults.string(forKey: defaultTabPathKey) ?? NSHomeDirectory()
    }

    func updateDefaultTabPath(_ path: String) {
        defaultTabPath = path
        userDefaults.set(path, forKey: defaultTabPathKey)
    }

    func resetDefaultTabPath() {
        updateDefaultTabPath(NSHomeDirectory())
    }

    func isValidPath(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
