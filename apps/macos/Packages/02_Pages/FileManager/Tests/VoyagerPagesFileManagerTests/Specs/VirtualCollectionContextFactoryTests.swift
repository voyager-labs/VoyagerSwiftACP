import VoyagerEntitiesCollection
import VoyagerFeaturesContentPageNavigation
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

final class VirtualCollectionContextFactoryTests: XCTestCase {
    func testTagsRouteMapsToRegistryDerivedTagCondition() throws {
        let context = try XCTUnwrap(
            FileManagerVirtualCollectionContextFactory.collectionContext(
                for: .tags("Work"),
                registryClient: makeRegistryClient(),
            ),
        )

        XCTAssertEqual(context.query, "")
        XCTAssertEqual(context.scopes, ["/"])
        XCTAssertEqual(context.excludedScopes, [])
        XCTAssertTrue(context.includeSubfolders)
        let condition = try XCTUnwrap(context.conditions.first)
        XCTAssertEqual(condition.propertyKey, "tag_names")
        XCTAssertEqual(condition.propertyLabel, "Registry Tag Label")
        XCTAssertEqual(condition.propertyType, "categorical")
        XCTAssertEqual(condition.operatorCode, "any")
        XCTAssertEqual(condition.operatorLabel, "Registry Any Label")
        XCTAssertEqual(condition.operatorValueArity, 1)
        XCTAssertEqual(condition.operatorValueUIKind, "listText")
        XCTAssertEqual(condition.valueType, "string_list")
        XCTAssertEqual(condition.values, ["Work"])
        XCTAssertTrue(condition.isActive)
    }

    func testRecentsRouteMapsToRegistryDerivedRecentCondition() throws {
        let context = try XCTUnwrap(
            FileManagerVirtualCollectionContextFactory.collectionContext(
                for: .recents,
                registryClient: makeRegistryClient(),
            ),
        )

        XCTAssertEqual(context.query, "")
        XCTAssertEqual(context.scopes, ["/"])
        XCTAssertEqual(context.excludedScopes, [])
        XCTAssertTrue(context.includeSubfolders)
        let condition = try XCTUnwrap(context.conditions.first)
        XCTAssertEqual(condition.propertyKey, "last_used_date")
        XCTAssertEqual(condition.propertyLabel, "Registry Last Used Label")
        XCTAssertEqual(condition.propertyType, "date")
        XCTAssertEqual(condition.operatorCode, "gt")
        XCTAssertEqual(condition.operatorLabel, "Registry Greater Than Label")
        XCTAssertEqual(condition.operatorValueArity, 1)
        XCTAssertEqual(condition.operatorValueUIKind, "singleDate")
        XCTAssertEqual(condition.valueType, "date")
        XCTAssertEqual(condition.values, [FileManagerVirtualCollectionContextFactory.recentsSinceAnyOpenedLiteral])
        XCTAssertTrue(condition.isActive)
    }

    func testFolderComputerAndCollectionRoutesDoNotSeedVirtualContext() {
        let registryClient = makeRegistryClient()
        XCTAssertNil(FileManagerVirtualCollectionContextFactory.collectionContext(
            for: .folder("/tmp"),
            registryClient: registryClient,
        ))
        XCTAssertNil(FileManagerVirtualCollectionContextFactory.collectionContext(
            for: .computer,
            registryClient: registryClient,
        ))
        XCTAssertNil(FileManagerVirtualCollectionContextFactory.collectionContext(
            for: .collection(.init(
                kind: .temporary,
                context: .init(),
                sortKey: .name,
                sortOrder: .ascending,
                viewLayout: .list,
            )),
            registryClient: registryClient,
        ))
    }

    private func makeRegistryClient() -> RegistryClient {
        RegistryClient(
            allProperties: { [] },
            labelForKey: Self.registryLabel(for:),
            propertyTypeString: Self.registryType(for:),
            propertyUnitSpec: { _ in nil },
            operatorCodes: { _ in ["any", "gt"] },
            operatorDefinition: Self.registryOperatorDefinition(for:),
            operatorValueUIKind: Self.registryOperatorUIKind(for:typeKey:),
            resolvePropertyKey: { .canonical($0) },
        )
    }

    private static func registryLabel(for key: String) -> String {
        switch key {
        case "tag_names": "Registry Tag Label"
        case "last_used_date": "Registry Last Used Label"
        default: key
        }
    }

    private static func registryType(for key: String) -> String {
        switch key {
        case "tag_names": "categorical"
        case "last_used_date": "date"
        default: "unknown"
        }
    }

    private static func registryOperatorDefinition(for code: String) -> OperatorDefinition {
        switch code {
        case "any":
            OperatorDefinition(
                uiLabel: "Registry Any Label",
                uiValueKind: ["categorical": "listText"],
            )
        case "gt":
            OperatorDefinition(
                uiLabel: "Registry Greater Than Label",
                uiValueKind: ["date": "singleDate"],
            )
        default:
            OperatorDefinition(uiLabel: code, uiValueKind: ["unknown": "singleText"])
        }
    }

    private static func registryOperatorUIKind(for code: String, typeKey: String) -> String {
        switch (code, typeKey) {
        case ("any", "categorical"):
            "listText"
        case ("gt", "date"):
            "singleDate"
        default:
            "singleText"
        }
    }
}
