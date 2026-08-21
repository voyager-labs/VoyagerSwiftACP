import Foundation
import VoyagerShared
import XCTest

final class RCL003SearchFilterPayloadsTests: XCTestCase {
    // MARK: - RCL-003-retrieve_entries_with_filters

    /// RCL-003-retrieve_entries_with_filters: search filters payload는 excludedScopes 누락을 빈 배열로 해석함
    /// 검색 필터 payload backward compatibility를 검증한다.
    /// - 검증 내용: `SearchFiltersPayload` decode 시 `excludedScopes`가 없으면 빈 배열로 보정
    /// - 사전 조건: legacy payload가 scopes와 conditions만 포함
    /// - 기대 결과: scopes/conditions/includeSubfolders는 유지되고 excludedScopes는 `[]`로 decode됨
    func testSearchFiltersPayloadDecodesMissingExcludedScopesAsEmpty() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "scopes": ["/Users/test/Documents"],
            "conditions": [],
        ])

        let decoded = try JSONDecoder().decode(SearchFiltersPayload.self, from: data)

        XCTAssertEqual(decoded.scopes, ["/Users/test/Documents"])
        XCTAssertEqual(decoded.excludedScopes, [])
        XCTAssertTrue(decoded.includeSubfolders)
        XCTAssertEqual(decoded.conditions, [])
    }

    /// RCL-003-retrieve_entries_with_filters: search filters payload는 excludedScopes를 round-trip 보존함
    /// 검색 요청 필터의 제외 scope 직렬화 계약을 검증한다.
    /// - 검증 내용: `SearchFiltersPayload` encode/decode 후 excludedScopes 포함 전체 payload 동등성 유지
    /// - 사전 조건: included scope와 excluded scope가 함께 설정됨
    /// - 기대 결과: decode 결과가 원본 payload와 동일함
    func testSearchFiltersPayloadRoundTripsExcludedScopes() throws {
        let payload = SearchFiltersPayload(
            scopes: ["/Users/test/Documents"],
            excludedScopes: ["/Users/test/Documents/Receipts"],
            includeSubfolders: true,
            conditions: [],
        )

        let decoded = try JSONDecoder().decode(SearchFiltersPayload.self, from: JSONEncoder().encode(payload))

        XCTAssertEqual(decoded, payload)
    }

    /// RCL-003-retrieve_entries_with_filters: applied filters payload는 excludedScopes 누락을 빈 배열로 해석함
    /// 검색 결과에 반영된 필터 payload backward compatibility를 검증한다.
    /// - 검증 내용: `AppliedFiltersPayload` decode 시 `excludedScopes`가 없으면 빈 배열로 보정
    /// - 사전 조건: legacy applied filters payload가 scopes와 conditions만 포함
    /// - 기대 결과: includeSubfolders는 nil로 유지되고 excludedScopes는 `[]`로 decode됨
    func testAppliedFiltersPayloadDecodesMissingExcludedScopesAsEmpty() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "scopes": ["/Users/test/Documents"],
            "conditions": [],
        ])

        let decoded = try JSONDecoder().decode(AppliedFiltersPayload.self, from: data)

        XCTAssertEqual(decoded.scopes, ["/Users/test/Documents"])
        XCTAssertEqual(decoded.excludedScopes, [])
        XCTAssertNil(decoded.includeSubfolders)
        XCTAssertEqual(decoded.conditions, [])
    }

    /// RCL-003-retrieve_entries_with_filters: applied filters payload는 excludedScopes를 round-trip 보존함
    /// 검색 결과 필터의 제외 scope 직렬화 계약을 검증한다.
    /// - 검증 내용: `AppliedFiltersPayload` encode/decode 후 excludedScopes 포함 전체 payload 동등성 유지
    /// - 사전 조건: applied filters payload에 include/exclude scope와 includeSubfolders가 설정됨
    /// - 기대 결과: decode 결과가 원본 payload와 동일함
    func testAppliedFiltersPayloadRoundTripsExcludedScopes() throws {
        let payload = AppliedFiltersPayload(
            scopes: ["/Users/test/Documents"],
            excludedScopes: ["/Users/test/Documents/Receipts"],
            includeSubfolders: false,
            conditions: [],
        )

        let decoded = try JSONDecoder().decode(AppliedFiltersPayload.self, from: JSONEncoder().encode(payload))

        XCTAssertEqual(decoded, payload)
    }

    /// RCL-003-retrieve_entries_with_filters: search response payload는 queryConversion 누락을 nil로 해석함
    /// 기존 검색 응답 payload와 query conversion metadata의 호환성을 검증한다.
    /// - 검증 내용: `SearchResponsePayload` decode 시 `queryConversion` key가 없으면 nil로 보정
    /// - 사전 조건: legacy response payload가 itemCount/appliedFilters/items/error만 포함
    /// - 기대 결과: decode 결과의 queryConversion이 nil임
    func testSearchResponsePayloadDecodesMissingQueryConversionAsNil() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "itemCount": 0,
            "appliedFilters": [
                "scopes": ["/Users/test/Documents"],
                "conditions": [],
            ],
            "items": NSNull(),
            "error": NSNull(),
        ])

        let decoded = try JSONDecoder().decode(SearchResponsePayload.self, from: data)

        XCTAssertNil(decoded.queryConversion)
    }

    /// RCL-003-retrieve_entries_with_filters: search response payload는 queryConversion metadata를 round-trip 보존함
    /// 검색 응답의 query conversion 결과 metadata 직렬화 계약을 검증한다.
    /// - 검증 내용: `SearchResponsePayload` encode/decode 후 queryConversion 포함 전체 payload 동등성 유지
    /// - 사전 조건: fallbackReuse query conversion metadata와 applied filters가 포함됨
    /// - 기대 결과: decode 결과가 원본 payload와 동일함
    func testSearchResponsePayloadRoundTripsQueryConversion() throws {
        let payload = SearchResponsePayload(
            itemCount: 0,
            appliedFilters: AppliedFiltersPayload(
                scopes: ["/Users/test/Documents"],
                excludedScopes: ["/Users/test/Documents/Receipts"],
                includeSubfolders: true,
                conditions: [],
            ),
            items: nil,
            error: nil,
            queryConversion: SearchQueryConversionMetadataPayload(outcome: .fallbackReuse),
        )

        let decoded = try JSONDecoder().decode(SearchResponsePayload.self, from: JSONEncoder().encode(payload))

        XCTAssertEqual(decoded, payload)
    }

    /// RCL-003-retrieve_entries_with_filters: recent search request payload는 scope와 sort 필드를 round-trip 보존함
    /// helper recent search 요청 payload의 공유 직렬화 계약을 검증한다.
    /// - 검증 내용: `RecentSearchRequestPayload` encode/decode 후 scopeMode, resultCap, includeHidden, sort 보존
    /// - 사전 조건: allIndexed scope와 lastUsedDateDescending sort가 설정됨
    /// - 기대 결과: round-trip 결과가 원본 payload와 동일함
    func testRecentSearchRequestPayloadRoundTripsScopeAndSortingFields() throws {
        let payload = RecentSearchRequestPayload(
            scopeMode: .allIndexed,
            scopes: [],
            resultCap: 100,
            includeHidden: false,
            sort: .lastUsedDateDescending,
        )

        let roundTripped = try JSONDecoder().decode(
            RecentSearchRequestPayload.self,
            from: JSONEncoder().encode(payload),
        )

        XCTAssertEqual(roundTripped, payload)
    }

    /// RCL-003-retrieve_entries_with_filters: tag search request payload는 exact verification 필드를 round-trip 보존함
    /// helper tag search 요청 payload의 공유 직렬화 계약을 검증한다.
    /// - 검증 내용: `TagSearchRequestPayload` encode/decode 후 requestedTag, scopes, exactTagVerification 보존
    /// - 사전 조건: scopedPaths scope와 exactTagVerification이 설정됨
    /// - 기대 결과: round-trip 결과가 원본 payload와 동일함
    func testTagSearchRequestPayloadRoundTripsExactVerificationFields() throws {
        let payload = TagSearchRequestPayload(
            requestedTag: "Work",
            scopeMode: .scopedPaths,
            scopes: ["/tmp"],
            resultCap: 100,
            includeHidden: true,
            sort: .lastUsedDateDescending,
            exactTagVerification: true,
        )

        let roundTripped = try JSONDecoder().decode(
            TagSearchRequestPayload.self,
            from: JSONEncoder().encode(payload),
        )

        XCTAssertEqual(roundTripped, payload)
    }

    /// RCL-003-retrieve_entries_with_filters: search entry payload는 tag와 source metadata를 round-trip 보존함
    /// helper 검색 결과 entry payload의 공유 직렬화 계약을 검증한다.
    /// - 검증 내용: `SearchEntryPayload` encode/decode 후 tags, creatorApplication, supplementaryMetadata 보존
    /// - 사전 조건: tag 색상, creator application, compressed file size metadata가 포함됨
    /// - 기대 결과: round-trip 결과가 원본 payload와 동일하고 tag/source metadata가 유지됨
    func testSearchEntryPayloadRoundTripsTagsAndSourceMetadata() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let payload = SearchEntryPayload(
            name: "Report.pdf",
            fullPath: "/tmp/Report.pdf",
            isFolder: false,
            isHidden: false,
            size: 42,
            modifiedDate: date,
            fileExtension: "pdf",
            createdDate: date,
            addedDate: date,
            lastOpenedDate: date,
            kind: "PDF",
            creatorApplication: "Preview",
            tags: [SearchTagPayload(name: "Work", colorCode: 4)],
            supplementaryMetadata: .compressedFileSize(42),
        )

        let roundTripped = try JSONDecoder().decode(
            SearchEntryPayload.self,
            from: JSONEncoder().encode(payload),
        )

        XCTAssertEqual(roundTripped, payload)
        XCTAssertEqual(roundTripped.tags?.first?.name, "Work")
        XCTAssertEqual(roundTripped.creatorApplication, "Preview")
    }

    /// RCL-003-retrieve_entries_with_filters: search entry payload는 isPackage를 encode→decode round-trip 보존함
    /// package 분류가 helper 검색 페이로드 직렬화에서 손실되지 않는지 검증한다.
    /// - 검증 내용: `SearchEntryPayload` encode/decode 후 isPackage 동등성 유지
    /// - 사전 조건: isPackage: true로 설정된 directory payload
    /// - 기대 결과: decode 결과가 원본 payload와 동일하고 isPackage가 true로 유지됨
    func testSearchEntryPayloadRoundTripsIsPackageTrue() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let payload = SearchEntryPayload(
            name: "Voyager.app",
            fullPath: "/tmp/Voyager.app",
            isFolder: true,
            isHidden: false,
            size: 0,
            modifiedDate: date,
            fileExtension: "app",
            createdDate: date,
            addedDate: date,
            lastOpenedDate: date,
            kind: "Folder",
            creatorApplication: nil,
            tags: nil,
            supplementaryMetadata: nil,
            isPackage: true,
        )

        let roundTripped = try JSONDecoder().decode(
            SearchEntryPayload.self,
            from: JSONEncoder().encode(payload),
        )

        XCTAssertEqual(roundTripped, payload)
        XCTAssertTrue(roundTripped.isPackage)
    }

    /// RCL-003-retrieve_entries_with_filters: legacy search entry payload는 isPackage 누락을 false로 해석함
    /// 기존 helper 검색 응답 페이로드와의 backward compatibility를 검증한다.
    /// - 검증 내용: `SearchEntryPayload` decode 시 isPackage key가 없으면 false로 보정
    /// - 사전 조건: isPackage key를 제외한 legacy directory payload
    /// - 기대 결과: decode가 성공하고 isPackage가 false로 해석됨
    func testSearchEntryPayloadDecodesMissingIsPackageAsFalse() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "name": "Voyager.app",
            "fullPath": "/tmp/Voyager.app",
            "isFolder": true,
            "isHidden": false,
            "size": 0,
            "modifiedDate": 1_700_000_000,
            "fileExtension": "app",
            "createdDate": 1_700_000_000,
            "addedDate": 1_700_000_000,
            "lastOpenedDate": 1_700_000_000,
            "kind": "Folder",
            "creatorApplication": NSNull(),
            "tags": NSNull(),
            "supplementaryMetadata": NSNull(),
        ])

        let decoded = try JSONDecoder().decode(SearchEntryPayload.self, from: data)

        XCTAssertFalse(decoded.isPackage)
        XCTAssertTrue(decoded.isFolder)
    }

    /// RCL-003-retrieve_entries_with_filters: legacy search entry payload는 필수 key 누락 시 여전히 throw함
    /// backward compatibility가 신규 key로만 한정되고 필수 legacy key는 여전히 보호되는지 검증한다.
    /// - 검증 내용: `SearchEntryPayload` decode 시 fullPath key가 없으면 실패
    /// - 사전 조건: fullPath를 제외한 legacy payload
    /// - 기대 결과: decode가 throw하고 isPackage false 보정이 필수 key 검증을 우회하지 않음
    func testSearchEntryPayloadDecodeThrowsWhenRequiredLegacyKeyMissing() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "name": "Voyager.app",
            "isFolder": true,
            "isHidden": false,
            "size": 0,
            "modifiedDate": 1_700_000_000,
            "fileExtension": "app",
            "createdDate": 1_700_000_000,
            "addedDate": 1_700_000_000,
            "lastOpenedDate": 1_700_000_000,
            "kind": "Folder",
            "creatorApplication": NSNull(),
            "tags": NSNull(),
            "supplementaryMetadata": NSNull(),
        ])

        XCTAssertThrowsError(try JSONDecoder().decode(SearchEntryPayload.self, from: data))
    }
}
