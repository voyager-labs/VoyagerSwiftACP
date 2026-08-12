import Foundation

struct EntryViewLayoutFixtureSandbox {
    let root: URL
    let fileURL: URL

    static func copyingFile(from relativePath: String) throws -> EntryViewLayoutFixtureSandbox {
        var root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while root.path != "/" {
            let fixture = root.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: fixture.path) {
                let sandbox = FileManager.default.temporaryDirectory
                    .appendingPathComponent("VoyagerEntryViewLayoutFixtureSandbox-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
                let fileURL = sandbox.appendingPathComponent(fixture.lastPathComponent)
                try FileManager.default.copyItem(at: fixture, to: fileURL)
                return .init(root: sandbox, fileURL: fileURL)
            }
            root.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
