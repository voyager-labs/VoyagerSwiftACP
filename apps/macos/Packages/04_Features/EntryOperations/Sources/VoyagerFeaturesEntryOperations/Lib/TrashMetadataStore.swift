import Foundation

struct TrashMetadata: Codable, Equatable {
    let trashPath: String
    let originalPath: String
    let deletedDate: Date
}

actor TrashMetadataStore {
    static let shared = TrashMetadataStore()

    private let plistURL: URL

    private init() {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
        ).first else {
            fatalError("Application Support directory not found")
        }

        self.init(plistURL: appSupport.appendingPathComponent("Voyager/trash_metadata.plist"))
    }

    init(plistURL: URL) {
        self.plistURL = plistURL
        try? Self.ensureParentDirectoryExists(for: plistURL)
    }

    func save(_ metadata: TrashMetadata) {
        guard var items = try? loadItems() else { return }
        items.append(metadata)
        write(items)
    }

    func load() -> [TrashMetadata] {
        (try? loadItems()) ?? []
    }

    func find(trashPath: String) -> TrashMetadata? {
        load().first { $0.trashPath == trashPath }
    }

    func remove(trashPath: String) {
        guard var items = try? loadItems() else { return }
        items.removeAll { $0.trashPath == trashPath }
        write(items)
    }

    func removeAll() {
        guard (try? loadItems()) != nil else { return }
        write([])
    }

    private func loadItems() throws -> [TrashMetadata] {
        try ensureParentDirectoryExists()
        guard FileManager.default.fileExists(atPath: plistURL.path) else { return [] }

        let data = try Data(contentsOf: plistURL)
        do {
            return try PropertyListDecoder().decode([TrashMetadata].self, from: data)
        } catch {
            try quarantineCorruptFile()
            return []
        }
    }

    private func quarantineCorruptFile() throws {
        try setOwnerOnlyFilePermissions(at: plistURL)
        let quarantineURL = plistURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(plistURL.lastPathComponent).corrupted-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: plistURL, to: quarantineURL)
    }

    private func write(_ items: [TrashMetadata]) {
        guard let data = try? PropertyListEncoder().encode(items) else { return }
        try? replaceFile(with: data)
    }

    private func replaceFile(with data: Data) throws {
        try ensureParentDirectoryExists()
        let tempURL = plistURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(plistURL.lastPathComponent).tmp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try data.write(to: tempURL, options: .atomic)
        try setOwnerOnlyFilePermissions(at: tempURL)

        if FileManager.default.fileExists(atPath: plistURL.path) {
            _ = try FileManager.default.replaceItemAt(plistURL, withItemAt: tempURL)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: plistURL)
        }
        try setOwnerOnlyFilePermissions(at: plistURL)
    }

    private func ensureParentDirectoryExists() throws {
        try Self.ensureParentDirectoryExists(for: plistURL)
    }

    nonisolated private static func ensureParentDirectoryExists(for plistURL: URL) throws {
        let directoryURL = plistURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700)],
            ofItemAtPath: directoryURL.path,
        )
    }

    private func setOwnerOnlyFilePermissions(at url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: url.path,
        )
    }
}
