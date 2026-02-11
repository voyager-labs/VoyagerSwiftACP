import ComposableArchitecture
import Foundation

// NOTE: FullDiskAccess 상태 타입은 권한 판정 클라이언트와 온보딩 권한 플로우에서 공용으로 사용한다.
// TODO: FullDiskAccessStatus와 message 규칙을 Settings/Model로 분리하고, Api는 클라이언트 인터페이스만 유지한다.
enum FullDiskAccessStatus: String, Equatable, Sendable {
    case granted = "Granted"
    case needsAction = "Needs Action"
    case denied = "Denied"
    case unknown = "Unknown"

    var message: String {
        switch self {
        case .granted:
            "You're all set for Full Disk Access."
        case .needsAction:
            "Turn on Full Disk Access to keep going."
        case .denied:
            "Full Disk Access is off. You can enable it anytime."
        case .unknown:
            "Check Full Disk Access in System Settings."
        }
    }
}

struct FullDiskAccessClient: Sendable {
    var status: @Sendable () -> FullDiskAccessStatus

    nonisolated init(status: @escaping @Sendable () -> FullDiskAccessStatus) {
        self.status = status
    }
}

extension FullDiskAccessClient: DependencyKey {
    nonisolated static var liveValue: FullDiskAccessClient {
        FullDiskAccessClient(status: {
            let fileManager = FileManager.default

            // Desktop 접근 시도: 권한이 없으면 시스템이 FDA 목록에 등록하도록 트리거
            let desktopPath = "\(NSHomeDirectory())/Desktop"
            do {
                _ = try fileManager.contentsOfDirectory(atPath: desktopPath)
                // Desktop 읽기 성공: Full Disk Access 권한 보유
                return .granted
            } catch {
                // Desktop 읽기 실패: 권한 이슈 가능, 이 접근 시도가 FDA 등록을 유도
            }

            // 보조 체크: 보호된 시스템 파일 접근 시도
            let protectedPaths = [
                "\(NSHomeDirectory())/Library/Safari/Bookmarks.plist",
                "/Library/Application Support/com.apple.TCC/TCC.db",
            ]

            for path in protectedPaths where fileManager.fileExists(atPath: path) {
                if fileManager.isReadableFile(atPath: path) {
                    return .granted
                } else {
                    // 파일은 존재하지만 읽기 불가: FDA 필요
                    return .needsAction
                }
            }

            // 판정 불가: 조치 필요로 처리
            return .needsAction
        })
    }

    nonisolated static var testValue: FullDiskAccessClient {
        FullDiskAccessClient(status: { .unknown })
    }

    nonisolated static var previewValue: FullDiskAccessClient {
        FullDiskAccessClient(status: { .unknown })
    }
}

extension DependencyValues {
    nonisolated var fullDiskAccessClient: FullDiskAccessClient {
        get { self[FullDiskAccessClient.self] }
        set { self[FullDiskAccessClient.self] = newValue }
    }
}
