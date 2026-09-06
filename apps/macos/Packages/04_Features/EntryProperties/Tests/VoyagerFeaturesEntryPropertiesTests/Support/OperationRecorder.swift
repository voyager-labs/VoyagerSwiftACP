actor OperationRecorder {
    private(set) var operations: [String] = []

    func record(_ operation: String) {
        operations.append(operation)
    }

    func values() -> [String] {
        operations
    }
}
