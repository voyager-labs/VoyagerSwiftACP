import Foundation

final class CallRecorder<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Value] = []

    func record(_ value: Value) {
        lock.lock()
        defer { lock.unlock() }
        values.append(value)
    }

    var recorded: [Value] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}
