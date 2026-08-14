import AppKit
import Foundation
import UniformTypeIdentifiers

final class DelayedFileURLItemProvider: @unchecked Sendable {
    let provider: NSItemProvider

    private let lock = NSLock()
    private var _loadCount = 0

    init(fileURL: URL, delay: TimeInterval = 0.05) {
        provider = NSItemProvider()
        let data = Data(fileURL.absoluteString.utf8)
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.fileURL.identifier,
            visibility: .all,
        ) { [weak self] completionHandler in
            self?.recordLoad()
            Thread.sleep(forTimeInterval: delay)
            completionHandler(data, nil)
            let progress = Progress(totalUnitCount: 1)
            progress.completedUnitCount = 1
            return progress
        }
    }

    var loadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _loadCount
    }

    private func recordLoad() {
        lock.lock()
        _loadCount += 1
        lock.unlock()
    }
}
