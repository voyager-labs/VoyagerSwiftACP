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
