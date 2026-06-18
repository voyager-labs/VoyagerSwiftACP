import Clocks
import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import VoyagerShared
import XCTest

// 트랜스크립트 스크롤 오프셋 persistence reducer 동작 검증.
// 로드, 클램프, 디바운스 지속화를 테스트한다.

@MainActor
final class AiChatFeatureTranscriptScrollOffsetTests: XCTestCase {
    private static let offsetsKey = "voyager.aiChat.transcriptScrollOffsets"

    // MARK: - onAppear 로드

    func testOnAppearLoadsExistingOffsets() async {
        let sessionID = AiChatSessionID(rawValue: UUID())
        let storedOffsets: [String: Double] = [sessionID.rawValue.uuidString: 150.0]
        let (udc, _) = makeStorageClient(seeded: storedOffsets)

        let store = TestStore(initialState: AiChatFeature.State()) {
            AiChatFeature()
        } withDependencies: {
            $0.userDefaultsClient = udc
        }

        await store.send(.onAppear)
        await store.receive(.transcriptScrollOffsetsLoaded([sessionID: 150.0])) {
            $0.transcriptScrollOffsets = [sessionID: 150.0]
        }
    }

    func testOnAppearLoadsEmptyWhenNoStoredData() async {
        let (udc, _) = makeStorageClient(seeded: nil)

        let store = TestStore(initialState: AiChatFeature.State()) {
            AiChatFeature()
        } withDependencies: {
            $0.userDefaultsClient = udc
        }

        await store.send(.onAppear)
        await store.receive(.transcriptScrollOffsetsLoaded([:]))
    }

    // MARK: - 오프셋 변경 + 클램프

    func testTranscriptScrollOffsetChangedClampsNegativeToZero() async {
        let clock = TestClock()
        let sessionID = AiChatSessionID(rawValue: UUID())
        let (udc, _) = makeStorageClient()

        let store = TestStore(initialState: AiChatFeature.State()) {
            AiChatFeature()
        } withDependencies: {
            $0.userDefaultsClient = udc
            $0.continuousClock = clock
        }

        await store.send(.transcriptScrollOffsetChanged(sessionID, -10)) {
            $0.transcriptScrollOffsets[sessionID] = 0
        }

        // 디바운스 대기
        await clock.advance(by: .milliseconds(300))
        await store.finish()
    }

    func testTranscriptScrollOffsetChangedStoresPositiveValue() async {
        let clock = TestClock()
        let sessionID = AiChatSessionID(rawValue: UUID())
        let (udc, wrapper) = makeStorageClient()

        let store = TestStore(initialState: AiChatFeature.State()) {
            AiChatFeature()
        } withDependencies: {
            $0.userDefaultsClient = udc
            $0.continuousClock = clock
        }

        await store.send(.transcriptScrollOffsetChanged(sessionID, 200)) {
            $0.transcriptScrollOffsets[sessionID] = 200
        }

        // 디바운스 대기
        await clock.advance(by: .milliseconds(300))
        await store.finish()

        // 저장 확인
        let saved = wrapper.read(Self.offsetsKey) as? [String: Double]
        XCTAssertEqual(saved?[sessionID.rawValue.uuidString], 200.0)
    }

    // MARK: - 디바운스: cancelInFlight

    func testRapidScrollChangesCancelPreviousPersistence() async {
        let clock = TestClock()
        let sessionID = AiChatSessionID(rawValue: UUID())
        let (udc, wrapper) = makeStorageClient()

        let store = TestStore(initialState: AiChatFeature.State()) {
            AiChatFeature()
        } withDependencies: {
            $0.userDefaultsClient = udc
            $0.continuousClock = clock
        }
        store.exhaustivity = .off

        // 첫 번째 변경
        await store.send(.transcriptScrollOffsetChanged(sessionID, 100))
        // 200ms 대기 (아직 디바운스 완료 전)
        await clock.advance(by: .milliseconds(200))
        // 두 번째 변경 — 첫 번째 이펙트 취소
        await store.send(.transcriptScrollOffsetChanged(sessionID, 300))
        // 300ms 대기 — 두 번째 이펙트 완료
        await clock.advance(by: .milliseconds(300))
        await store.finish()

        // 최종 값 300이 저장됨
        let saved = wrapper.read(Self.offsetsKey) as? [String: Double]
        XCTAssertEqual(saved?[sessionID.rawValue.uuidString], 300.0)
    }

    // MARK: - Helpers

    private func makeStorageClient(
        seeded: Any? = nil,
    ) -> (UserDefaultsClient, LockedStorage) {
        let storage = LockedStorage(seeded: seeded, key: Self.offsetsKey)
        return (storage.makeClient(), storage)
    }
}

// MARK: - 테스트 헬퍼

private final class LockedStorage: @unchecked Sendable {
    private var storage: [String: Any] = [:]
    private let lock = NSLock()

    init(seeded: Any?, key: String) {
        if let seeded { storage[key] = seeded }
    }

    func read(_ key: String) -> Any? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    func makeClient() -> UserDefaultsClient {
        UserDefaultsClient(
            bool: { [lock] key in
                lock.lock()
                defer { lock.unlock() }
                return self.storage[key] as? Bool ?? false
            },
            setBool: { [lock] value, key in
                lock.lock()
                defer { lock.unlock() }
                self.storage[key] = value
            },
            string: { [lock] key in
                lock.lock()
                defer { lock.unlock() }
                return self.storage[key] as? String
            },
            setString: { [lock] value, key in
                lock.lock()
                defer { lock.unlock() }
                self.storage[key] = value
            },
            double: { [lock] key in
                lock.lock()
                defer { lock.unlock() }
                return self.storage[key] as? Double ?? 0
            },
            setDouble: { [lock] value, key in
                lock.lock()
                defer { lock.unlock() }
                self.storage[key] = value
            },
            object: { [lock] key in
                lock.lock()
                defer { lock.unlock() }
                return self.storage[key]
            },
            setObject: { [lock] value, key in
                lock.lock()
                defer { lock.unlock() }
                if let value {
                    self.storage[key] = value
                } else {
                    self.storage.removeValue(forKey: key)
                }
            },
        )
    }
}
