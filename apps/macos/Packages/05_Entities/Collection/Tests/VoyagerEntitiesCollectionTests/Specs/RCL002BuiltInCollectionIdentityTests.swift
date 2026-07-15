import Foundation
@testable import VoyagerEntitiesCollection
import VoyagerShared
import XCTest

@MainActor
final class RCL002BuiltInCollectionIdentityTests: XCTestCase {
    // MARK: - RCL-002-ensure_built_in_collections

    /// RCL-002-ensure_built_in_collections: built-in Collection identity metadata를 안정적으로 제공한다.
    /// 앱이 Recents와 All Tags를 생성할 때 영속 ID, package filename, 표시 이름 계약을 재사용하는 경로를 검증한다.
    /// - 검증 내용: 전체 identity의 raw ID, package filename, canonical Collection name
    /// - 사전 조건: 별도 filesystem 조회 없이 `BuiltInCollectionIdentity.allCases` 사용
    /// - 기대 결과: Recents와 All Tags metadata가 제품 계약과 정확히 일치함
    func testIdentityMetadata_matchesStableContract() {
        XCTAssertEqual(BuiltInCollectionIdentity.allCases, [.recents, .allTags])
        XCTAssertEqual(BuiltInCollectionIdentity.recents.rawValue, "recents")
        XCTAssertEqual(BuiltInCollectionIdentity.recents.packageFilename, "recents.voycoll")
        XCTAssertEqual(BuiltInCollectionIdentity.recents.collectionName, "Recents")
        XCTAssertEqual(BuiltInCollectionIdentity.allTags.rawValue, "all_tags")
        XCTAssertEqual(BuiltInCollectionIdentity.allTags.packageFilename, "all-tags.voycoll")
        XCTAssertEqual(BuiltInCollectionIdentity.allTags.collectionName, "All Tags")
    }

    /// RCL-002-ensure_built_in_collections: injected Application Support 아래 canonical package URL을 조립한다.
    /// 앱이 사용자 도메인 Application Support 위치를 주입하면 built-in root와 item URL이 결정되는 경로를 검증한다.
    /// - 검증 내용: `Voyager/Collections/BuiltIn` root와 identity별 package URL
    /// - 사전 조건: Application Support fixture URL은 `/tmp/Application Support`
    /// - 기대 결과: exact root 아래에 `recents.voycoll`과 `all-tags.voycoll` URL이 생성됨
    func testCanonicalURLs_buildFromInjectedApplicationSupportURL() {
        let applicationSupportURL = URL(fileURLWithPath: "/tmp/Application Support", isDirectory: true)
        let rootURL = BuiltInCollectionIdentity.canonicalRootURL(
            applicationSupportURL: applicationSupportURL,
        )

        XCTAssertEqual(rootURL.path, "/tmp/Application Support/Voyager/Collections/BuiltIn")
        XCTAssertEqual(
            BuiltInCollectionIdentity.recents.canonicalPackageURL(
                applicationSupportURL: applicationSupportURL,
            ).path,
            "/tmp/Application Support/Voyager/Collections/BuiltIn/recents.voycoll",
        )
        XCTAssertEqual(
            BuiltInCollectionIdentity.allTags.canonicalPackageURL(
                applicationSupportURL: applicationSupportURL,
            ).path,
            "/tmp/Application Support/Voyager/Collections/BuiltIn/all-tags.voycoll",
        )
    }

    /// RCL-002-ensure_built_in_collections: standardized canonical package URL을 identity로 역분류한다.
    /// 앱이 lexical path variant를 전달해도 standardized exact package 위치라면 동일 built-in으로 인식하는 경로를 검증한다.
    /// - 검증 내용: 두 canonical URL과 `..`을 포함한 standardized path의 positive classification
    /// - 사전 조건: Application Support fixture URL은 `/tmp/Application Support`
    /// - 기대 결과: canonical Recents와 All Tags URL만 각 identity로 round-trip됨
    func testClassification_acceptsExactStandardizedPackagePaths() {
        let applicationSupportURL = URL(fileURLWithPath: "/tmp/Application Support", isDirectory: true)
        let recentsURL = BuiltInCollectionIdentity.recents.canonicalPackageURL(
            applicationSupportURL: applicationSupportURL,
        )
        let allTagsURL = URL(
            fileURLWithPath: "/tmp/Application Support/Voyager/Collections/BuiltIn/nested/../all-tags.voycoll",
        )

        XCTAssertEqual(
            BuiltInCollectionIdentity.classify(
                packageURL: recentsURL,
                applicationSupportURL: applicationSupportURL,
            ),
            .recents,
        )
        XCTAssertEqual(
            BuiltInCollectionIdentity.classify(
                packageURL: allTagsURL,
                applicationSupportURL: applicationSupportURL,
            ),
            .allTags,
        )
    }

    /// RCL-002-ensure_built_in_collections: canonical package 밖의 유사 URL을 built-in으로 분류하지 않는다.
    /// 사용자 Collection이나 prefix가 겹치는 package가 app-managed built-in으로 오인되지 않는 경로를 검증한다.
    /// - 검증 내용: sibling, parent, 외부 동일 filename, prefix-collision URL의 negative classification
    /// - 사전 조건: Application Support fixture URL은 `/tmp/Application Support`
    /// - 기대 결과: exact canonical package path가 아닌 모든 URL은 nil로 거부됨
    func testClassification_rejectsNonCanonicalAndPrefixCollisionPaths() {
        let applicationSupportURL = URL(fileURLWithPath: "/tmp/Application Support", isDirectory: true)
        let rejectedURLs = [
            URL(fileURLWithPath: "/tmp/Application Support/Voyager/Collections/recents.voycoll"),
            URL(fileURLWithPath: "/tmp/Application Support/Voyager/Collections/BuiltIn"),
            URL(fileURLWithPath: "/tmp/Elsewhere/recents.voycoll"),
            URL(fileURLWithPath: "/tmp/Application Support/Voyager/Collections/BuiltIn/recents.voycoll-copy"),
        ]

        for packageURL in rejectedURLs {
            XCTAssertNil(
                BuiltInCollectionIdentity.classify(
                    packageURL: packageURL,
                    applicationSupportURL: applicationSupportURL,
                ),
                "Unexpected built-in classification for \(packageURL.path)",
            )
        }
    }

    func testManagedPathPolicy_resolutionFailureBlocksLexicalCanonicalOnly() {
        let applicationSupportURL = URL(
            fileURLWithPath: "/nonexistent/Application Support",
            isDirectory: true,
        )
        let canonicalURL = BuiltInCollectionIdentity.recents.canonicalPackageURL(
            applicationSupportURL: applicationSupportURL,
        )
        let nonCanonicalURL = applicationSupportURL.appendingPathComponent("User.voycoll")
        var fileManagerClient = FileManagerClient.testValue
        fileManagerClient.urlsForDirectory = { _, _ in [applicationSupportURL] }
        fileManagerClient.fileExists = { _ in true }

        XCTAssertTrue(BuiltInCollectionManagedPathPolicy.isCanonicalDestination(
            canonicalURL,
            fileManagerClient: fileManagerClient,
        ))
        XCTAssertFalse(BuiltInCollectionManagedPathPolicy.isCanonicalDestination(
            nonCanonicalURL,
            fileManagerClient: fileManagerClient,
        ))
    }
}
