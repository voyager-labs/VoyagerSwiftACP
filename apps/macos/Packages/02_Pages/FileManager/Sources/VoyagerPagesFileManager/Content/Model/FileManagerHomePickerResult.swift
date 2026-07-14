import Foundation

public enum FileManagerHomePickerResult<Value: Equatable & Sendable>: Equatable, Sendable {
    case selected(Value)
    case cancelled
    case failed(String)
}
