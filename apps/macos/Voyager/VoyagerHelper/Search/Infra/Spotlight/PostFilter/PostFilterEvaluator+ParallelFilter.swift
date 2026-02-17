import Foundation

extension PostFilterEvaluator {
    func shouldEvaluateInParallel(pathCount: Int) -> Bool {
        pathCount >= 1024 && ProcessInfo.processInfo.activeProcessorCount > 1
    }

    func filterPathsSequentially(
        paths: [String],
        specs: [ConditionSpec],
        nsurlSymbols: Set<String>,
    ) throws -> [String] {
        var filtered: [String] = []
        filtered.reserveCapacity(paths.count)

        for path in paths {
            var context = PathContext(path: path)
            preloadNSURLResourceValues(symbols: nsurlSymbols, context: &context)
            if try matchesAll(specs: specs, context: &context) {
                filtered.append(path)
            }
        }

        return filtered
    }

    func filterPathsInParallel(
        paths: [String],
        specs: [ConditionSpec],
        nsurlSymbols: Set<String>,
    ) throws -> [String] {
        let workerCount = min(ProcessInfo.processInfo.activeProcessorCount, paths.count)
        let state = ParallelFilterState(workerCount: workerCount)

        DispatchQueue.concurrentPerform(iterations: workerCount) { workerIndex in
            var localMatches: [(Int, String)] = []
            localMatches.reserveCapacity(max(paths.count / max(workerCount, 1), 1))

            var index = workerIndex
            while index < paths.count {
                if state.shouldStop() {
                    break
                }

                let path = paths[index]
                do {
                    var context = PathContext(path: path)
                    preloadNSURLResourceValues(symbols: nsurlSymbols, context: &context)
                    if try matchesAll(specs: specs, context: &context) {
                        localMatches.append((index, path))
                    }
                } catch {
                    state.record(error: error)
                    break
                }

                index += workerCount
            }

            state.store(localMatches, at: workerIndex)
        }

        if let firstError = state.firstError {
            throw firstError
        }

        var ordered = [String?](repeating: nil, count: paths.count)
        for partial in state.results {
            for (index, path) in partial {
                ordered[index] = path
            }
        }
        return ordered.compactMap(\.self)
    }
}

private final nonisolated class ParallelFilterState: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var firstError: Error?
    private(set) var results: [[(Int, String)]]

    init(workerCount: Int) {
        results = Array(repeating: [], count: workerCount)
    }

    func shouldStop() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return firstError != nil
    }

    func record(error: Error) {
        lock.lock()
        if firstError == nil {
            firstError = error
        }
        lock.unlock()
    }

    func store(_ partial: [(Int, String)], at workerIndex: Int) {
        lock.lock()
        results[workerIndex] = partial
        lock.unlock()
    }
}
