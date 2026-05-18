@testable import VoyagerEntitiesTag
import XCTest

/// Characterization tests for TagMDItemUserTagParser behavior.
/// These tests lock down the current parsing behavior for MDItem kMDItemUserTags format.
/// Format: "name\ncolorCode" (e.g., "blue\n6")
@MainActor
final class TagMDItemUserTagParserTests: XCTestCase {
    // MARK: - parse(_:) Tests

    /// Test that valid color code is preserved during parsing.
    /// Expected: "blue\n6" → Tag(name: "blue", colorCode: 6)
    func testParse_WithValidColorCode_ReturnsTagWithCorrectColorCode() {
        let result = TagMDItemUserTagParser.parse("blue\n6")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "blue")
        XCTAssertEqual(result?.colorCode, 6)
    }

    /// Test that invalid (non-numeric) color code falls back to 0.
    /// Expected: "blue\nxyz" → Tag(name: "blue", colorCode: 0)
    func testParse_WithInvalidColorCode_FallsBackToZero() {
        let result = TagMDItemUserTagParser.parse("blue\nxyz")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "blue")
        XCTAssertEqual(result?.colorCode, 0)
    }

    /// Test that tag without color code gets colorCode 0.
    /// Expected: "blue" → Tag(name: "blue", colorCode: 0)
    func testParse_WithoutColorCode_ReturnsZero() {
        let result = TagMDItemUserTagParser.parse("blue")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "blue")
        XCTAssertEqual(result?.colorCode, 0)
    }

    /// Test that empty name returns nil.
    /// Expected: "" → nil
    func testParse_WithEmptyName_ReturnsNil() {
        let result = TagMDItemUserTagParser.parse("")

        XCTAssertNil(result)
    }

    /// Test that whitespace-only name returns nil.
    /// Expected: "   " → nil
    func testParse_WithWhitespaceOnlyName_ReturnsNil() {
        let result = TagMDItemUserTagParser.parse("   ")

        XCTAssertNil(result)
    }

    /// Test that name with leading/trailing whitespace is trimmed.
    /// Expected: "  blue  \n6" → Tag(name: "blue", colorCode: 6)
    func testParse_TrimsWhitespaceFromName() {
        let result = TagMDItemUserTagParser.parse("  blue  \n6")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "blue")
        XCTAssertEqual(result?.colorCode, 6)
    }

    /// Test that color code with trailing whitespace/newline is parsed correctly.
    /// Expected: "blue\n6  " → Tag(name: "blue", colorCode: 6)
    func testParse_TrimsWhitespaceFromColorCode() {
        let result = TagMDItemUserTagParser.parse("blue\n6  ")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "blue")
        XCTAssertEqual(result?.colorCode, 6)
    }

    /// Test that zero color code is preserved.
    /// Expected: "blue\n0" → Tag(name: "blue", colorCode: 0)
    func testParse_WithZeroColorCode_ReturnsZero() {
        let result = TagMDItemUserTagParser.parse("blue\n0")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "blue")
        XCTAssertEqual(result?.colorCode, 0)
    }

    /// Test that negative color code is parsed (Finder allows 1-7, but parser accepts any Int).
    /// Expected: "blue\n-1" → Tag(name: "blue", colorCode: -1)
    func testParse_WithNegativeColorCode_ReturnsNegativeValue() {
        let result = TagMDItemUserTagParser.parse("blue\n-1")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "blue")
        XCTAssertEqual(result?.colorCode, -1)
    }

    // MARK: - parseRelaxed(_:defaultColorCode:) Tests

    /// Test that parseRelaxed falls back to parse when valid.
    /// Expected: "blue\n6" → Tag(name: "blue", colorCode: 6)
    func testParseRelaxed_WithValidFormat_ReturnsParsedTag() {
        let result = TagMDItemUserTagParser.parseRelaxed("blue\n6")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "blue")
        XCTAssertEqual(result?.colorCode, 6)
    }

    /// Test that parseRelaxed with name-only uses default color code.
    /// Expected: "blue" → Tag(name: "blue", colorCode: 0)
    func testParseRelaxed_WithInvalidInput_ReturnsTagWithDefaultColorCode() {
        let result = TagMDItemUserTagParser.parseRelaxed("blue")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "blue")
        XCTAssertEqual(result?.colorCode, 0)
    }

    /// Test that parseRelaxed with custom defaultColorCode uses it.
    /// Expected: "blue" with defaultColorCode: 5 → Tag(name: "blue", colorCode: 5)
    func testParseRelaxed_WithCustomDefaultColorCode_UsesCustomDefault() {
        let result = TagMDItemUserTagParser.parseRelaxed("blue", defaultColorCode: 5)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "blue")
        XCTAssertEqual(result?.colorCode, 5)
    }

    /// Test that parseRelaxed with empty name returns nil.
    /// Expected: "" → nil
    func testParseRelaxed_WithEmptyName_ReturnsNil() {
        let result = TagMDItemUserTagParser.parseRelaxed("")

        XCTAssertNil(result)
    }

    /// Test that parseRelaxed with whitespace-only name returns nil.
    /// Expected: "   " → nil
    func testParseRelaxed_WithWhitespaceOnlyName_ReturnsNil() {
        let result = TagMDItemUserTagParser.parseRelaxed("   ")

        XCTAssertNil(result)
    }

    /// Test that parseRelaxed trims whitespace from name.
    /// Expected: "  blue  " → Tag(name: "blue", colorCode: 0)
    func testParseRelaxed_TrimsWhitespaceFromName() {
        let result = TagMDItemUserTagParser.parseRelaxed("  blue  ")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "blue")
        XCTAssertEqual(result?.colorCode, 0)
    }

    // MARK: - Edge Cases

    /// Test that multiple newlines are handled (only first split counts).
    /// Expected: "blue\n6\nextra" → Tag(name: "blue", colorCode: 6) - "extra" is part of colorCode string which fails
    /// Int()
    func testParse_WithMultipleNewlines_HandlesGracefully() {
        // Note: maxSplits: 1 means we get at most 2 components
        // "blue\n6\nextra" → ["blue", "6\nextra"]
        // Int("6\nextra") fails, so colorCode becomes 0
        let result = TagMDItemUserTagParser.parse("blue\n6\nextra")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "blue")
        XCTAssertEqual(result?.colorCode, 0) // Int("6\nextra") fails
    }

    /// Test various valid Finder color codes (1-7).
    func testParse_WithFinderColorCodes_ReturnsCorrectColorCode() {
        let colorCodes = [1, 2, 3, 4, 5, 6, 7]

        for code in colorCodes {
            let result = TagMDItemUserTagParser.parse("tag\n\(code)")
            XCTAssertEqual(result?.colorCode, code, "Expected colorCode \(code) for input 'tag\\n\(code)'")
        }
    }
}
