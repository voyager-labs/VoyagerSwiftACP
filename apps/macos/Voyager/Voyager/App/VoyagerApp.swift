import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_: Notification) {
        // 앱 종료 시 핀 탭 저장
        PinnedTabsManager.shared.saveToPlist()
    }
}

@main
struct VoyagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    var appDelegate

    init() {
        launchHelperOnce()
    }

    var body: some Scene {
        WindowGroup {
            FileManagerView()
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            MenuCommands()
        }
    }

    func launchHelperOnce() {
        // 헬퍼 앱 경로 계산 (메인 앱과 같은 빌드 디렉토리)
        let mainURL = Bundle.main.bundleURL
        let buildDir = mainURL.deletingLastPathComponent()
        let helperURL = buildDir.appendingPathComponent("VoyagerHelper.app")

        guard FileManager.default.fileExists(atPath: helperURL.path) else { return }

        // 이미 실행 중인 헬퍼 앱 확인
        let runningApps = NSWorkspace.shared.runningApplications
        let isHelperRunning = runningApps.contains { app in
            app.bundleIdentifier == "fm.vayager.VoyagerHelper"
        }

        if !isHelperRunning {
            // 헬퍼 앱 실행 설정
            let config = NSWorkspace.OpenConfiguration()
            config.environment = ProcessInfo.processInfo.environment // 메인 앱 환경변수 전달

            // 헬퍼 앱을 독립 프로세스로 실행
            NSWorkspace.shared.openApplication(at: helperURL, configuration: config) { _, _ in
                // 헬퍼 앱 실행 완료
            }
        }
    }
}
