import ComposableArchitecture
import Foundation
@testable import VoyagerPagesFileManager

@MainActor
func makeFileManagerContentStore(
    initialState: FileManagerContentState = FileManagerContentState(),
    setString: @escaping @Sendable (String, String) -> Void = { _, _ in },
) -> TestStore<FileManagerContentState, FileManagerContentAction> {
    TestStore(initialState: initialState) {
        FileManagerContentComposerReducer()
    } withDependencies: {
        $0.userDefaultsClient.setString = setString
    }
}

/// FileManagerContentFeature(전체 리듀서) 기반 TestStore 생성 헬퍼
/// ComposerReducer만 사용하는 기존 헬퍼와 달리 네비게이션·히스토리·entryOperations까지 포함한다.
@MainActor
func makeFileManagerContentFeatureStore(
    initialState: FileManagerContentState = FileManagerContentState(),
    setString: @escaping @Sendable (String, String) -> Void = { _, _ in },
    date: Date = Date(timeIntervalSince1970: 0),
) -> TestStore<FileManagerContentState, FileManagerContentAction> {
    TestStore(initialState: initialState) {
        FileManagerContentFeature()
    } withDependencies: {
        $0.userDefaultsClient.setString = setString
        $0.date = .constant(date)
    }
}

final class UserDefaultsStringRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func record(_ value: String, _ key: String) {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }

    func value(forKey key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }
}
