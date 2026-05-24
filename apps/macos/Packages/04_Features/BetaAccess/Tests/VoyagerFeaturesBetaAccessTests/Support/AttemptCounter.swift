import Foundation

/// 스레드 안전한 호출 카운터 — 비동기 재시도 테스트에서 검증 클라이언트가 몇 번 호출되었는지 추적합니다.
///
/// `@unchecked Sendable`로 선언된 이유: Swift 6 strict concurrency에서
/// `@Sendable` 클로저 내부에서 mutable `var`를 직접 캡처할 수 없기 때문입니다.
/// `NSLock`으로 `_value` 접근을 보호하여 스레드 안전성을 수동으로 보장합니다.
/// 재시도 스케줄링이 깨지면 `counter.value` 단언이 실패하여 회귀를 감지합니다.
final class AttemptCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0

    var value: Int {
        lock.withLock { _value }
    }

    func increment() -> Int {
        lock.withLock {
            _value += 1
            return _value
        }
    }
}
