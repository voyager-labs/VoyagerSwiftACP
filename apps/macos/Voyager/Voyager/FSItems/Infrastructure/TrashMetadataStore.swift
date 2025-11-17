import Foundation

struct TrashMetadata: Codable, Equatable, Sendable {
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
            in: .userDomainMask
        ).first else {
            fatalError("Application Support directory not found")
        }

        let voyagerDir = appSupport.appendingPathComponent("Voyager")

        try? FileManager.default.createDirectory(
            at: voyagerDir,
            withIntermediateDirectories: true
        )

        plistURL = voyagerDir.appendingPathComponent("trash_metadata.plist")
    }

    func save(_ metadata: TrashMetadata) {
        var items = load()
        items.append(metadata)
        write(items)
    }

    func load() -> [TrashMetadata] {
        guard let data = try? Data(contentsOf: plistURL),
              let items = try? PropertyListDecoder().decode([TrashMetadata].self, from: data)
        else { return [] }

        return items
    }

    func find(trashPath: String) -> TrashMetadata? {
        load().first { $0.trashPath == trashPath }
    }

    func remove(trashPath: String) {
        var items = load()
        items.removeAll { $0.trashPath == trashPath }
        write(items)
    }

    func removeAll() {
        write([])
    }

    private func write(_ items: [TrashMetadata]) {
        guard let data = try? PropertyListEncoder().encode(items) else { return }
        try? data.write(to: plistURL)
    }
}
