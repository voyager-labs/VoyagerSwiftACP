@testable import VoyagerEntitiesAi
import XCTest

final class AiModelCatalogTests: XCTestCase {
    func testV1Catalog_rowsRemainUniquelyAddressable() {
        let handles = AiModelCatalogFixture.v1Catalog.map(\.handle)
        let labels = AiModelCatalogFixture.v1Catalog.map(\.displayName)

        XCTAssertEqual(Set(handles).count, handles.count)
        XCTAssertEqual(Set(labels).count, labels.count)
    }

    func testV1Catalog_bindsEachRowToProviderDescriptorMetadata() {
        for row in AiModelCatalogFixture.v1Catalog {
            let descriptor = ProviderDescriptor.descriptor(for: row.handle.provider)

            XCTAssertNotNil(descriptor)
            XCTAssertEqual(row.authMethod, descriptor?.authMethod)
            XCTAssertEqual(row.subtitle, descriptor?.displayName)
        }
    }

    func testV1Catalog_marksAtMostOneDefaultRow() {
        XCTAssertLessThanOrEqual(AiModelCatalogFixture.v1Catalog.filter(\.isDefault).count, 1)
    }

    func testRowFor_knownHandleReturnsMatchingRow() {
        guard let expectedRow = AiModelCatalogFixture.v1Catalog.first else {
            return XCTFail("Expected at least one catalog row fixture")
        }

        let row = AiModelCatalogFixture.row(for: expectedRow.handle)

        XCTAssertEqual(row, expectedRow)
    }

    func testRowFor_unknownHandleReturnsNil() {
        XCTAssertNil(AiModelCatalogFixture.row(for: AiModelHandle(provider: .openai, rawValue: "gpt-5")))
        XCTAssertNil(AiModelCatalogFixture.row(for: AiModelHandle(provider: .chatgptCodex, rawValue: "codex-preview")))
    }
}
