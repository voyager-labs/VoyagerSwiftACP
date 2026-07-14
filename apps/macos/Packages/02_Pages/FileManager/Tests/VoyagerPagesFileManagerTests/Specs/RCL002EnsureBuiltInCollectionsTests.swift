@_spi(Internals)
import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerEntitiesTag
@testable import VoyagerPagesFileManager
import XCTest

@MainActor
final class RCL002EnsureBuiltInCollectionsTests: XCTestCase {
    // MARK: - RCL-002-ensure_built_in_collections

    func testAdapter_normalizesFinderTagsAndBuildsCanonicalContexts() async throws {
        let captured = LockIsolated<(CollectionContext, CollectionContext?)?>(nil)
        let client = FileManagerBuiltInCollectionClient.liveValue

        let report = await withDependencies {
            $0.finderFavoritesTagClient.favoriteTagNames = { [" Work ", "Personal", "Work"] }
            $0.registryClient = BuiltInCollectionAdapterTestRegistry.client
            $0.builtInCollectionClient.ensureAll = { recentsContext, allTagsContext in
                captured.setValue((recentsContext, allTagsContext))
                return .init(recents: .failed, allTags: .failed)
            }
        } operation: {
            await client.ensureAll()
        }

        XCTAssertEqual(report, .init(recents: .failed, allTags: .failed))
        let contexts = try XCTUnwrap(captured.value)
        XCTAssertEqual(contexts.0.conditions.map(\.propertyKey), ["last_used_date", "content_type_tree"])
        XCTAssertFalse(contexts.0.includeDirectories)
        XCTAssertEqual(contexts.1?.conditions.first?.values, ["Personal", "Work"])
        XCTAssertEqual(contexts.1?.includeDirectories, true)
    }

    func testAdapter_zeroFinderTagsDefersAllTagsContextToEntity() async {
        let captured = LockIsolated<(CollectionContext, CollectionContext?)?>(nil)
        let client = FileManagerBuiltInCollectionClient.liveValue

        let report = await withDependencies {
            $0.finderFavoritesTagClient.favoriteTagNames = { [" ", "\t\n"] }
            $0.registryClient = BuiltInCollectionAdapterTestRegistry.client
            $0.builtInCollectionClient.ensureAll = { recentsContext, allTagsContext in
                captured.setValue((recentsContext, allTagsContext))
                return .init(recents: .failed, allTags: .deferred)
            }
        } operation: {
            await client.ensureAll()
        }

        XCTAssertEqual(report, .init(recents: .failed, allTags: .deferred))
        XCTAssertNotNil(captured.value?.0)
        XCTAssertNil(captured.value?.1)
    }
}

private enum BuiltInCollectionAdapterTestRegistry {
    static let client = RegistryClient(
        allProperties: { [] },
        labelForKey: { key in key },
        propertyTypeString: { key in
            switch key {
            case "tag_names": "categorical"
            case "last_used_date": "date"
            case "content_type_tree": "string"
            default: "unknown"
            }
        },
        propertyUnitSpec: { _ in nil },
        operatorCodes: { _ in ["any", "gt", "neq"] },
        operatorDefinition: { code in
            OperatorDefinition(uiLabel: code, uiValueKind: nil)
        },
        operatorValueUIKind: { code, typeKey in
            switch (code, typeKey) {
            case ("any", "categorical"): "listText"
            case ("gt", "date"): "singleDate"
            default: "singleText"
            }
        },
        resolvePropertyKey: { .canonical($0) },
    )
}
