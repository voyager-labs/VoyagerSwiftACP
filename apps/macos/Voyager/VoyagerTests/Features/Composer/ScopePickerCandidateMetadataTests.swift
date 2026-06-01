@testable import Voyager
import XCTest

@MainActor
final class ScopePickerCandidateMetadataTests: XCTestCase {
    func testCandidateItemDisplayMetadataDefaultsAndPreservesExplicitValues() {
        let defaultCandidate = ComposerScopeEditorCandidateItem(
            path: "/Users/me/Documents",
            name: "Documents",
            iconName: "folder",
        )

        XCTAssertNil(defaultCandidate.locationIdentifier)
        XCTAssertNil(defaultCandidate.secondaryText)
        XCTAssertEqual(defaultCandidate.id, "/Users/me/Documents")

        let configuredCandidate = ComposerScopeEditorCandidateItem(
            path: "/Users/me/Documents",
            name: "Documents",
            iconName: "folder",
            locationIdentifier: "/Users/me",
            secondaryText: "Documents",
        )

        XCTAssertEqual(configuredCandidate.locationIdentifier, "/Users/me")
        XCTAssertEqual(configuredCandidate.secondaryText, "Documents")
    }

    func testApplyCandidateDisambiguationPolicyKeepsSecondaryTextNilForNonDuplicateNames() {
        let items = [
            ComposerScopeUtils.DirectoryItem(
                id: "/Users/me/Documents",
                path: "/Users/me/Documents",
                name: "Documents",
                iconName: "folder",
                locationIdentifier: "/Users/me",
            ),
            ComposerScopeUtils.DirectoryItem(
                id: "/Users/me/Downloads",
                path: "/Users/me/Downloads",
                name: "Downloads",
                iconName: "folder",
                locationIdentifier: "/Users/me",
            ),
        ]

        let result = ComposerScopeUtils.applyCandidateDisambiguationPolicy(items)

        XCTAssertEqual(result.map(\.id), items.map(\.id))
        XCTAssertEqual(result.map(\.path), items.map(\.path))
        XCTAssertEqual(result.map(\.name), items.map(\.name))
        XCTAssertEqual(result.map(\.iconName), items.map(\.iconName))
        XCTAssertEqual(result.map(\.locationIdentifier), items.map(\.locationIdentifier))
        XCTAssertTrue(result.allSatisfy { $0.secondaryText == nil })
    }

    func testApplyCandidateDisambiguationPolicyUsesParentNamesForDuplicateNames() {
        let items = [
            ComposerScopeUtils.DirectoryItem(
                id: "/Users/me/Work/Docs",
                path: "/Users/me/Work/Docs",
                name: "Docs",
                iconName: "folder",
                locationIdentifier: "/Users/me/Work",
            ),
            ComposerScopeUtils.DirectoryItem(
                id: "/Users/me/Personal/Docs",
                path: "/Users/me/Personal/Docs",
                name: "Docs",
                iconName: "folder",
                locationIdentifier: "/Users/me/Personal",
            ),
        ]

        let result = ComposerScopeUtils.applyCandidateDisambiguationPolicy(items)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(Set(result.map(\.locationIdentifier)).count, 2)
        XCTAssertEqual(Set(result.compactMap(\.secondaryText)), ["Work", "Personal"])
        XCTAssertEqual(result[0].secondaryText, "Work")
        XCTAssertEqual(result[1].secondaryText, "Personal")
    }

    func testApplyCandidateDisambiguationPolicyExpandsSuffixWhenParentNamesMatch() {
        let items = [
            ComposerScopeUtils.DirectoryItem(
                id: "/Users/me/Work/Projects/Docs",
                path: "/Users/me/Work/Projects/Docs",
                name: "Docs",
                iconName: "folder",
                locationIdentifier: "/Users/me/Work/Projects",
            ),
            ComposerScopeUtils.DirectoryItem(
                id: "/Users/me/Personal/Projects/Docs",
                path: "/Users/me/Personal/Projects/Docs",
                name: "Docs",
                iconName: "folder",
                locationIdentifier: "/Users/me/Personal/Projects",
            ),
        ]

        let result = ComposerScopeUtils.applyCandidateDisambiguationPolicy(items)

        XCTAssertEqual(
            Set(result.map(\.locationIdentifier)),
            ["/Users/me/Work/Projects", "/Users/me/Personal/Projects"],
        )
        XCTAssertEqual(Set(result.compactMap(\.secondaryText)), ["Work/Projects", "Personal/Projects"])
    }

    func testApplyCandidateDisambiguationPolicyUsesStorageFallbackForMixedLocations() {
        let items = [
            ComposerScopeUtils.DirectoryItem(
                id: "/Volumes/External/Work/Docs",
                path: "/Volumes/External/Work/Docs",
                name: "Docs",
                iconName: "folder",
                locationIdentifier: "/Volumes/External/Work",
            ),
            ComposerScopeUtils.DirectoryItem(
                id: "/Users/me/Work/Docs",
                path: "/Users/me/Work/Docs",
                name: "Docs",
                iconName: "folder",
                locationIdentifier: "/Users/me/Work",
            ),
        ]

        let result = ComposerScopeUtils.applyCandidateDisambiguationPolicy(items)

        XCTAssertEqual(Set(result.compactMap(\.secondaryText)), ["External • Work", "me • Work"])
    }

    func testApplyCandidateDisambiguationPolicyUsesAbsoluteParentPathAsLastResortWhenOtherLabelsStillCollide() {
        let items = [
            ComposerScopeUtils.DirectoryItem(
                id: "/Volumes/me/Work/Docs",
                path: "/Volumes/me/Work/Docs",
                name: "Docs",
                iconName: "folder",
                locationIdentifier: "/Volumes/me/Work",
            ),
            ComposerScopeUtils.DirectoryItem(
                id: "/Users/me/Work/Docs",
                path: "/Users/me/Work/Docs",
                name: "Docs",
                iconName: "folder",
                locationIdentifier: "/Users/me/Work",
            ),
        ]

        let result = ComposerScopeUtils.applyCandidateDisambiguationPolicy(items)

        // last resort: volume name and username are both `me`, so suffix and storage fallback stay ambiguous.
        XCTAssertEqual(Set(result.compactMap(\.secondaryText)), ["/Volumes/me/Work", "/Users/me/Work"])
    }

    func testDefaultAndSearchCandidatesShareLocationMetadataContract() {
        let defaultCandidates = makeDefaultScopeEditorCandidates(
            favorites: [],
            backHistory: ["/Users/me/Work/Docs"],
            entryLoadingClient: makeEntryLoadingClient(),
        )

        let searchItems = [
            ComposerScopeUtils.DirectoryItem(
                id: "/Users/me/Work/Docs",
                path: "/Users/me/Work/Docs",
                name: "Docs",
                iconName: "folder",
                locationIdentifier: "/Users/me/Work",
            ),
        ]
        let searchCandidate = ComposerScopeEditorCandidateItem(
            path: searchItems[0].path,
            name: searchItems[0].name,
            iconName: searchItems[0].iconName,
            locationIdentifier: searchItems[0].locationIdentifier,
        )

        XCTAssertEqual(defaultCandidates.first?.locationIdentifier, searchCandidate.locationIdentifier)
        XCTAssertNil(defaultCandidates.first?.secondaryText)
        XCTAssertNil(searchCandidate.secondaryText)
    }

    func testCandidateRowsExposeSecondaryTextWithoutChangingSelectionIntent() {
        let state = ComposerScopeEditorState(
            selection: .explicit(
                bases: [ComposerScopeBase(path: "/Users/me/Documents")],
                exceptions: [],
            ),
            includeSubfolders: true,
            isPresented: true,
            editingPath: "/Users/me/Documents",
            entryMode: .edit,
            candidateItems: [
                ComposerScopeEditorCandidateItem(
                    path: "/Users/me/Documents/Secrets",
                    name: "Secrets",
                    iconName: "folder",
                    locationIdentifier: "/Users/me/Documents",
                ),
                ComposerScopeEditorCandidateItem(
                    path: "/Users/me/Archive/Secrets",
                    name: "Secrets",
                    iconName: "folder",
                    locationIdentifier: "/Users/me/Archive",
                ),
            ],
        )

        XCTAssertEqual(
            state.candidateSelectionIntent(for: "/Users/me/Documents/Secrets"),
            .exclude(path: "/Users/me/Documents/Secrets"),
        )
        let candidates = state.sections().last?.items.compactMap { item -> ComposerScopeEditorCandidateItem? in
            guard case let .addableCandidate(candidate) = item else { return nil }
            return candidate
        }
        XCTAssertEqual(candidates?.map(\.secondaryText), ["Documents", "Archive"])
        XCTAssertTrue(state.candidateItems.allSatisfy { $0.secondaryText == nil })
    }

    func testCurrentScopeFilteringRecomputesSecondaryTextForVisibleCandidates() {
        let state = ComposerScopeEditorState(
            selection: .explicit(
                bases: [ComposerScopeBase(path: "/Users/me/Work/Docs")],
                exceptions: [],
            ),
            listState: .defaultCandidates,
            isPresented: true,
            queryText: "",
            editingPath: nil,
            candidateItems: ComposerScopeUtils.applyCandidateDisambiguationPolicy(
                [
                    ComposerScopeUtils.DirectoryItem(
                        id: "/Users/me/Work/Docs",
                        path: "/Users/me/Work/Docs",
                        name: "Docs",
                        iconName: "folder",
                        locationIdentifier: "/Users/me/Work",
                    ),
                    ComposerScopeUtils.DirectoryItem(
                        id: "/Users/me/Personal/Docs",
                        path: "/Users/me/Personal/Docs",
                        name: "Docs",
                        iconName: "folder",
                        locationIdentifier: "/Users/me/Personal",
                    ),
                ],
            )
            .map { item in
                ComposerScopeEditorCandidateItem(
                    path: item.path,
                    name: item.name,
                    iconName: item.iconName,
                    locationIdentifier: item.locationIdentifier,
                    secondaryText: item.secondaryText,
                )
            },
        )

        let candidates = state.sections().last?.items.compactMap { item -> ComposerScopeEditorCandidateItem? in
            guard case let .addableCandidate(candidate) = item else { return nil }
            return candidate
        }

        XCTAssertEqual(candidates?.map(\.path), ["/Users/me/Personal/Docs"])
        XCTAssertEqual(candidates?.first?.locationIdentifier, "/Users/me/Personal")
        XCTAssertNil(candidates?.first?.secondaryText)
    }

    func testCandidateRowsDoNotForceSecondaryForNonDuplicateCandidates() {
        let state = ComposerScopeEditorState(
            selection: .explicit(
                bases: [ComposerScopeBase(path: "/Users/me/Documents")],
                exceptions: [],
            ),
            listState: .defaultCandidates,
            isPresented: true,
            queryText: "",
            editingPath: nil,
            candidateItems: [
                ComposerScopeEditorCandidateItem(path: "/Users/me/Downloads", name: "Downloads", iconName: "folder"),
            ],
        )

        let sections = state.sections()

        XCTAssertEqual(sections.map(\.kind.id), ["current-scopes", "addable-default"])
        guard let sectionItem = sections[1].items.first else {
            return XCTFail("expected addable candidate")
        }
        guard case let .addableCandidate(candidate) = sectionItem else {
            return XCTFail("expected addable candidate")
        }
        XCTAssertNil(candidate.secondaryText)
    }

    func testMakeDefaultScopeEditorCandidatesKeepsRawMetadataOnly() {
        let candidates = makeDefaultScopeEditorCandidates(
            favorites: [],
            backHistory: [
                "/Users/me/Work/Docs",
                "/Users/me/Personal/Docs",
                "/Users/me/Downloads",
            ],
            entryLoadingClient: makeEntryLoadingClient(),
        )

        let duplicateCandidates = candidates.filter { $0.name == "Docs" }
        XCTAssertEqual(duplicateCandidates.count, 2)
        XCTAssertEqual(Set(duplicateCandidates.map(\.path)), [
            "/Users/me/Personal/Docs",
            "/Users/me/Work/Docs",
        ])
        XCTAssertEqual(Set(duplicateCandidates.map(\.locationIdentifier)), [
            "/Users/me/Personal",
            "/Users/me/Work",
        ])
        XCTAssertTrue(duplicateCandidates.allSatisfy { $0.secondaryText == nil })

        let downloadsCandidate = candidates.first(where: { $0.name == "Downloads" })
        XCTAssertEqual(downloadsCandidate?.locationIdentifier, "/Users/me")
        XCTAssertNil(downloadsCandidate?.secondaryText)
    }

    private func makeEntryLoadingClient(homePath: String = "/Users/me") -> EntryLoadingClient {
        var client = EntryLoadingClient.testValue
        client.fileExists = { _ in true }
        client.displayName = { ($0 as NSString).lastPathComponent }
        client.homeDirectory = { homePath }
        client.urlsForDirectory = { _, _ in [] }
        return client
    }
}
