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
        discoveredLocationIDs: [String] = [],
    ) -> Result {
        guard !completion else { return .suppressed }

        return switch ensureResult {
        case let .ready(descriptor):
            evaluateReady(
                descriptor: descriptor,
                store: store,
                now: now,
                maxRecordCount: maxRecordCount,
                discoveredLocationIDs: discoveredLocationIDs,
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
        discoveredLocationIDs: [String],
    ) -> Result {
        let metadata = metadata(for: descriptor.identity)
        let stableIDMatch = store.records.first { $0.id == metadata.stableID }
        let selectedRecord = stableIDMatch ?? store.records.first {
            $0.collectionFileURL == descriptor.canonicalPackageURL
        }

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
        let remainingRecords = store.records.filter {
            $0.id != metadata.stableID && $0.collectionFileURL != descriptor.canonicalPackageURL
        }
        let replacedRecords = store.records.lazy.filter { record in
            record.id == metadata.stableID || record.collectionFileURL == descriptor.canonicalPackageURL
        }
        let replacedRecordIDs = Set(replacedRecords.map { ContentTabID(rawValue: $0.id) })
        let baseStore = ContentTabPinnedRecordStore(
            schemaVersion: store.schemaVersion,
            records: remainingRecords + [canonicalRecord],
            topNavigationOrder: .init(items: store.topNavigationOrder.items.filter { item in
                guard case let .contentTab(id) = item else { return true }
                return !replacedRecordIDs.contains(id)
            }),
        )
        let normalized = FileManagerTopNavigationOrderPolicy.normalize(
            store: baseStore,
            discoveredLocationIDs: discoveredLocationIDs,
        ).normalizedStore
        var finalStore = normalized
        finalStore.topNavigationOrder = FileManagerTopNavigationOrderPolicy.insertingPinnedItem(
            ContentTabID(rawValue: metadata.stableID),
            into: normalized.topNavigationOrder,
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
