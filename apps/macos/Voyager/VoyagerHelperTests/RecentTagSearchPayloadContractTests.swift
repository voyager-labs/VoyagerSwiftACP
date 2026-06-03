import Foundation
@testable import VoyagerHelper
import VoyagerShared
import XCTest

final class RecentTagSearchPayloadContractTests: XCTestCase {
    func testRecentRequestRoundTripsScopeAndSortingFields() throws {
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

    func testTagRequestRoundTripsExactVerificationFields() throws {
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

    func testEntryPayloadRoundTripsWithoutPathOnlyRegression() throws {
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
}
