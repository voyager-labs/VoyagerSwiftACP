import Foundation

final class MutationRecorder<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedValues: [T] = []

    func record(_ value: T) {
        lock.lock()
        defer { lock.unlock() }
        recordedValues.append(value)
    }

    var values: [T] {
        lock.lock()
        defer { lock.unlock() }
        return recordedValues
    }
}
