import Foundation

/// copy effect 취소를 검증하기 위한 동기화 gate.
/// - `wait()`: 복사 task가 pasteFile에 도달하면 첫 도달을 `waitForStart()`로 알리고, 열릴 때까지 대기한다.
/// - `waitForStart()`: 복사 task가 pasteFile gate에 도달했을 때(즉 cancellable 등록이 끝난 뒤) 반환한다.
/// - `open()`: 대기 중인 continuation을 모두 재개한다. 취소 시 onCancel에서 호출해 task가 CancellationError로 빠져나가게 한다.
final class PasteCancellationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var opened = false
    private var started = false
    private var startContinuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if opened {
                lock.unlock()
                continuation.resume()
                return
            }
            if !started {
                started = true
                startContinuation?.resume()
                startContinuation = nil
            }
            continuations.append(continuation)
            lock.unlock()
        }
    }

    func waitForStart() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if started {
                lock.unlock()
                continuation.resume()
                return
            }
            startContinuation = continuation
            lock.unlock()
        }
    }

    func open() {
        lock.lock()
        opened = true
        let pending = continuations
        continuations.removeAll()
        lock.unlock()
        pending.forEach { $0.resume() }
    }
}
