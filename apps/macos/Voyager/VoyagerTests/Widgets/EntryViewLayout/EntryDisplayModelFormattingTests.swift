@testable import Voyager
import VoyagerEntitiesEntry
import XCTest

/// 포맷팅 회귀를 검증하는 테스트 모음이다.
@MainActor
final class EntryDisplayModelFormattingTests: XCTestCase {
    /// 서식/출력 경계 회귀를 방지한다.
    func testFormatsSizeAndDatesAndSupplementaryInfoLikeEquivalentFormatters() throws {
        let modifiedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let createdDate = Date(timeIntervalSince1970: 1_700_000_123)

        let display = EntryDisplayModel(entry: makeEntry(
            isFolder: false,
            size: 12_345_678,
            modifiedDate: modifiedDate,
            createdDate: createdDate,
            supplementaryMetadata: .compressedFileSize(9_876_543),
        ))

        XCTAssertEqual(display.formattedSize, byteFormatter().string(fromByteCount: 12_345_678))
        XCTAssertEqual(display.formattedModifiedDate, dateFormatter().string(from: modifiedDate))
        XCTAssertEqual(display.formattedCreatedDate, dateFormatter().string(from: createdDate))
        XCTAssertEqual(display.supplementaryInfoText, archiveSizeFormatter().string(fromByteCount: 9_876_543))
    }

    /// 서식/출력 경계 회귀를 방지한다.
    func testFormatsFolderAndMetadataEdgeCasesExactly() throws {
        let display = EntryDisplayModel(entry: makeEntry(
            isFolder: true,
            size: 1,
            modifiedDate: Date(timeIntervalSince1970: 1_700_000_000),
            createdDate: Date(timeIntervalSince1970: 1_700_000_000),
            supplementaryMetadata: nil,
        ))

        XCTAssertEqual(display.formattedSize, "--")

        let emptyFolder = EntryDisplayModel(entry: makeEntry(
            isFolder: true,
            size: 0,
            modifiedDate: Date(timeIntervalSince1970: 1_700_000_000),
            createdDate: Date(timeIntervalSince1970: 1_700_000_000),
            supplementaryMetadata: .folderItemCount(0),
        ))
        XCTAssertEqual(emptyFolder.supplementaryInfoText, "No items")

        let singularFolder = EntryDisplayModel(entry: makeEntry(
            isFolder: true,
            size: 0,
            modifiedDate: Date(timeIntervalSince1970: 1_700_000_000),
            createdDate: Date(timeIntervalSince1970: 1_700_000_000),
            supplementaryMetadata: .folderItemCount(1),
        ))
        XCTAssertEqual(singularFolder.supplementaryInfoText, "1 item")

        let pluralFolder = EntryDisplayModel(entry: makeEntry(
            isFolder: true,
            size: 0,
            modifiedDate: Date(timeIntervalSince1970: 1_700_000_000),
            createdDate: Date(timeIntervalSince1970: 1_700_000_000),
            supplementaryMetadata: .folderItemCount(2),
        ))
        XCTAssertEqual(pluralFolder.supplementaryInfoText, "2 items")

        let resolution = EntryDisplayModel(entry: makeEntry(
            isFolder: false,
            size: 0,
            modifiedDate: Date(timeIntervalSince1970: 1_700_000_000),
            createdDate: Date(timeIntervalSince1970: 1_700_000_000),
            supplementaryMetadata: .imageResolution(width: 1920, height: 1080),
        ))
        XCTAssertEqual(resolution.supplementaryInfoText, "1920 × 1080")
    }

    private func makeEntry(
        isFolder: Bool,
        size: Int64,
        modifiedDate: Date,
        createdDate: Date,
        supplementaryMetadata: EntrySupplementaryMetadata?,
    ) -> EntryModel {
        EntryModel(
            name: "Example",
            fullPath: "/tmp/example",
            isFolder: isFolder,
            isHidden: false,
            size: size,
            modifiedDate: modifiedDate,
            fileExtension: "txt",
            facets: EntryFacets(
                createdDate: createdDate,
                addedDate: createdDate,
                lastOpenedDate: nil,
                kind: "Text",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: supplementaryMetadata,
            ),
        )
    }

    private func dateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    private func byteFormatter() -> ByteCountFormatter {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }

    private func archiveSizeFormatter() -> ByteCountFormatter {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }
}
