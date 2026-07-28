@testable import VoyagerEntitiesCollection
import XCTest

@MainActor
extension RCL002OpenSavedCollectionTests {
    /// RCL-002-open_saved_collection_legacy: 모든 공개 release의 저장 shape는 현재 decoder로 열린다.
    /// tag별 실제 schema/field 진화 계약을 binary plist로 재현해 빠진 release 구간이 없음을 검증한다.
    /// - 검증 내용: v0.0.1-v0.8.3 전체 tag, legacy Int/object schema, 추가 field 기본값
    /// - 사전 조건: release source에서 추출한 25개 persistence case
    /// - 기대 결과: 모든 payload가 schema 1.0 definition으로 복원되고 누락 field는 당시 기본값을 사용함
    func testOpenSavedCollection_acrossAllHistoricalReleases_restoresPersistedDefinition() throws {
        XCTAssertEqual(HistoricalCollectionReleaseFixture.all.count, 25)

        for release in HistoricalCollectionReleaseFixture.all {
            let result = try VoyagerCollectionFileCompatibilityOwner.decode(
                release.encodedPayload(),
                containerFormat: .package,
            )

            XCTAssertEqual(result.file.appVersion, release.tag, release.tag)
            XCTAssertEqual(result.file.schemaVersion, SchemaVersion(major: 1, minor: 0), release.tag)
            XCTAssertEqual(result.file.excludedScopes, release.excludedScopes ?? [], release.tag)
            XCTAssertEqual(result.file.includeSubfolders, release.includeSubfolders ?? true, release.tag)
            XCTAssertEqual(result.file.includeDirectories, release.includeDirectories ?? false, release.tag)
        }
    }
}
