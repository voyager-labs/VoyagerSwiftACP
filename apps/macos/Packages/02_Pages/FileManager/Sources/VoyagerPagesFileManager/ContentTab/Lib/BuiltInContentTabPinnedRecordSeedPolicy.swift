import Foundation
import VoyagerEntitiesCollection

public enum BuiltInContentTabPinnedRecordSeedPolicy {
    public struct VerifiedDescriptor: Equatable, Sendable {
        public let identity: BuiltInCollectionIdentity
        public let canonicalPackageURL: URL

        public init(identity: BuiltInCollectionIdentity, canonicalPackageURL: URL) {
            self.identity = identity
            self.canonicalPackageURL = canonicalPackageURL
        }
    }

    public enum EnsureResult: Equatable, Sendable {
        case ready(VerifiedDescriptor)
        case deferred
        case failed
    }

    public enum Result: Equatable, Sendable {
        case seed(ContentTabPinnedRecordStore)
        case alreadyPresent(ContentTabPinnedRecordStore)
        case suppressed
        case deferred
        case failed
    }

    private struct Metadata {
        let stableID: String
        let title: String
        let iconName: String
    }

    public static func containsCanonicalRecord(
        in store: ContentTabPinnedRecordStore,
        descriptor: VerifiedDescriptor,
    ) -> Bool {
        let metadata = metadata(for: descriptor.identity)
        return store.records.contains { record in
            record.id == metadata.stableID
                && record.page == .collection
                && record.anchor == .collectionFile(url: descriptor.canonicalPackageURL)
        }
    }

    public static func classify(
        _ record: ContentTabPinnedRecord,
        applicationSupportURL: URL?,
    ) -> BuiltInCollectionIdentity? {
        if let identity = BuiltInCollectionIdentity.allCases.first(where: { identity in
            record.id == metadata(for: identity).stableID
        }) {
            return identity
        }
        guard let applicationSupportURL,
              let packageURL = record.collectionFileURL
        else { return nil }
        return BuiltInCollectionIdentity.classify(
            packageURL: packageURL,
            applicationSupportURL: applicationSupportURL,
        )
    }

    public static func records(
        classifiedAs identity: BuiltInCollectionIdentity,
        in store: ContentTabPinnedRecordStore,
        applicationSupportURL: URL?,
    ) -> [ContentTabPinnedRecord] {
        store.records.filter {
            classify($0, applicationSupportURL: applicationSupportURL) == identity
        }
    }

    public static func evaluate(
        ensureResult: EnsureResult,
        completion: Bool,
        store: ContentTabPinnedRecordStore,
        now: Date,
        maxRecordCount: Int = ContentTabConstants.maxTabs,
    ) -> Result {
        guard !completion else { return .suppressed }

        return switch ensureResult {
        case let .ready(descriptor):
            evaluateReady(
                descriptor: descriptor,
                store: store,
                now: now,
                maxRecordCount: maxRecordCount,
            )
        case .deferred:
            .deferred
        case .failed:
            .failed
        }
    }

    private static func evaluateReady(
        descriptor: VerifiedDescriptor,
        store: ContentTabPinnedRecordStore,
        now: Date,
        maxRecordCount: Int,
    ) -> Result {
        let metadata = metadata(for: descriptor.identity)
        let selectedRecordIndex = store.records.firstIndex { $0.id == metadata.stableID }
            ?? store.records.firstIndex { $0.collectionFileURL == descriptor.canonicalPackageURL }
        let selectedRecord = selectedRecordIndex.map { store.records[$0] }

        guard selectedRecord != nil || store.records.count < maxRecordCount else {
            return .deferred
        }

        let canonicalRecord = ContentTabPinnedRecord(
            id: metadata.stableID,
            page: .collection,
            anchor: .collectionFile(url: descriptor.canonicalPackageURL),
            title: metadata.title,
            iconName: metadata.iconName,
            pinnedAt: selectedRecord?.pinnedAt ?? now,
        )
        let isMatchingRecord: (ContentTabPinnedRecord) -> Bool = {
            $0.id == metadata.stableID || $0.collectionFileURL == descriptor.canonicalPackageURL
        }
        var records = store.records.filter { !isMatchingRecord($0) }
        let insertionIndex = selectedRecordIndex.map { selectedIndex in
            store.records[..<selectedIndex].count { !isMatchingRecord($0) }
        } ?? records.endIndex
        records.insert(canonicalRecord, at: insertionIndex)
        let finalStore = ContentTabPinnedRecordStore(
            schemaVersion: store.schemaVersion,
            records: records,
        )

        return selectedRecord == nil ? .seed(finalStore) : .alreadyPresent(finalStore)
    }

    private static func metadata(
        for identity: BuiltInCollectionIdentity,
    ) -> Metadata {
        switch identity {
        case .recents:
            Metadata(stableID: "built-in-collection-recents", title: "Recents", iconName: "clock")
        case .allTags:
            Metadata(stableID: "built-in-collection-all-tags", title: "All Tags", iconName: "tag")
        }
    }
}

private extension ContentTabPinnedRecord {
    var collectionFileURL: URL? {
        guard case let .collectionFile(url) = anchor else { return nil }
        return url
    }
}
