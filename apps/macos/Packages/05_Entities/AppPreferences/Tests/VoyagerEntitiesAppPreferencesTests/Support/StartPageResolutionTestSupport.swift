import Foundation
import VoyagerEntitiesAppPreferences
import VoyagerShared

/*
 SET-002-configure_initial_page 테스트 지원 파일 (flat Support 규칙)

 - 레거시 StartPageResolverTests.swift 에서 이동한 fixture/double만 포함한다.
 - 제품 동작을 소유하지 않는다.
 */

/// UserDefaults 쓰기를 기록하는 in-memory double. 폴백 경로의 비저장(no-persistence) 검증에 사용한다.
final class RecordingUserDefaults: @unchecked Sendable {
    var values: [String: String] = [:]
    var writeCount = 0

    var client: UserDefaultsClient {
        UserDefaultsClient(
            bool: { _ in false },
            setBool: { _, _ in self.writeCount += 1 },
            string: { key in self.values[key] },
            setString: { value, key in
                self.writeCount += 1
                self.values[key] = value
            },
            double: { _ in 0 },
            setDouble: { _, _ in self.writeCount += 1 },
            object: { _ in nil },
            setObject: { _, _ in self.writeCount += 1 },
        )
    }
}

/// 가용성 probe 호출 횟수를 세는 스레드 안전 카운터.
final class Counter: @unchecked Sendable {
    var value = 0
}

/// live probe 성공 경로 검증용 임시 디렉터리 fixture.
struct FileManagerFixtureSandbox {
    let root: URL
    let directory: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoyagerAppPreferencesFixture-\(UUID().uuidString)", isDirectory: true)
        directory = root.appendingPathComponent("directory", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
