import Foundation
@testable import Voyager
import XCTest

@MainActor
final class ScopePickerViewModelTests: XCTestCase {
    func testSectionsInlineExceptionsUnderCurrentScopes() {
        let state = ComposerScopeEditorState(
            selection: .explicit(
                bases: [ComposerScopeBase(path: "/Users/me/Documents"), ComposerScopeBase(path: "/Users/me/Desktop")],
                exceptions: [
                    ComposerScopeException(path: "/Users/me/Documents/Secrets"),
                    ComposerScopeException(path: "/Users/me/Documents/Archive"),
                ],
            ),
            listState: .defaultCandidates,
            isPresented: true,
            queryText: "",
            editingPath: "/Users/me/Documents",
            candidateItems: [
                ComposerScopeEditorCandidateItem(path: "/Users/me/Documents", name: "Documents", iconName: "folder"),
                ComposerScopeEditorCandidateItem(path: "/Users/me/Downloads", name: "Downloads", iconName: "folder"),
            ],
        )

        let sections = state.sections()

        XCTAssertEqual(sections.map(\.kind.id), ["current-scopes", "addable-default"])
        XCTAssertEqual(sections.first?.id, "current-scopes")
        XCTAssertEqual(sections[0].items.map(\.id), [
            "current-/Users/me/Documents",
            "exception-/Users/me/Documents-/Users/me/Documents/Secrets",
            "exception-/Users/me/Documents-/Users/me/Documents/Archive",
            "current-/Users/me/Desktop",
        ])

        guard case let .currentScope(firstCurrent) = sections[0].items[0] else {
            return XCTFail("expected current scope item")
        }
        XCTAssertTrue(firstCurrent.isEditingTarget)
        XCTAssertEqual(firstCurrent.exceptionCount, 2)
        XCTAssertEqual(firstCurrent.exceptionSummaryText, "2 exceptions")

        guard case let .exceptionScope(firstException) = sections[0].items[1] else {
            return XCTFail("expected first inline exception item")
        }
        XCTAssertEqual(firstException.path, "/Users/me/Documents/Secrets")
        XCTAssertEqual(firstException.owningBasePath, "/Users/me/Documents")

        guard case let .currentScope(secondCurrent) = sections[0].items[3] else {
            return XCTFail("expected second current scope item")
        }
        XCTAssertEqual(secondCurrent.base.path, "/Users/me/Desktop")
        XCTAssertEqual(secondCurrent.exceptionCount, 0)
        XCTAssertNil(secondCurrent.exceptionSummaryText)

        XCTAssertEqual(sections[1].items.count, 1)
        guard case let .addableCandidate(candidate) = sections[1].items.first else {
            return XCTFail("expected addable candidate")
        }
        XCTAssertEqual(candidate.path, "/Users/me/Downloads")
    }

    func testRootOnlyShowsSuggestionsWithoutCurrentScopesSection() {
        let state = ComposerScopeEditorState(
            selection: .rootOnly,
            listState: .defaultCandidates,
            isPresented: true,
            queryText: "",
            candidateItems: [
                ComposerScopeEditorCandidateItem(path: "/Users/me/Documents", name: "Documents", iconName: "folder"),
            ],
        )

        let sections = state.sections()

        XCTAssertEqual(sections.map(\.kind.id), ["addable-default"])
        XCTAssertFalse(sections.flatMap(\.items).contains { $0.id.contains("exception-") })
    }

    func testNoResultsSectionKeepsCurrentScopesVisibleWithoutExceptionPlaceholder() {
        let state = ComposerScopeEditorState(
            selection: .explicit(
                bases: [ComposerScopeBase(path: "/Users/me/Documents")],
                exceptions: [],
            ),
            listState: .noResults(query: "docs"),
            isPresented: true,
            queryText: "docs",
            editingPath: nil,
            candidateItems: [],
        )

        let sections = state.sections()

        XCTAssertEqual(sections.map(\.kind.id), ["current-scopes", "addable-empty-docs"])
        XCTAssertEqual(sections[0].items.count, 1)
        XCTAssertEqual(sections[1].items.count, 0)
        XCTAssertEqual(sections[1].kind.id, "addable-empty-docs")
        XCTAssertFalse(sections.flatMap(\.items).contains { $0.id.contains("exception-") })
    }

    func testCandidateSelectionIntentExcludesDescendantWhenEditingBase() {
        let state = ComposerScopeEditorState(
            selection: .explicit(
                bases: [ComposerScopeBase(path: "/Users/me/Documents")],
                exceptions: [],
            ),
            includeSubfolders: true,
            isPresented: true,
            editingPath: "/Users/me/Documents",
            entryMode: .edit,
        )

        XCTAssertEqual(
            state.candidateSelectionIntent(for: "/Users/me/Documents/Secrets/"),
            .exclude(path: "/Users/me/Documents/Secrets"),
        )
    }

    func testCandidateSelectionIntentReplacesWhenEditingNonDescendantOrExactFolderMode() {
        let editState = ComposerScopeEditorState(
            selection: .explicit(
                bases: [ComposerScopeBase(path: "/Users/me/Documents")],
                exceptions: [],
            ),
            includeSubfolders: true,
            isPresented: true,
            editingPath: "/Users/me/Documents",
            entryMode: .edit,
        )

        XCTAssertEqual(
            editState.candidateSelectionIntent(for: "/Users/me/Desktop"),
            .replace(oldPath: "/Users/me/Documents", newPath: "/Users/me/Desktop"),
        )

        let exactFolderState = ComposerScopeEditorState(
            selection: .explicit(
                bases: [ComposerScopeBase(path: "/Users/me/Documents")],
                exceptions: [],
            ),
            includeSubfolders: false,
            isPresented: true,
            editingPath: "/Users/me/Documents",
            entryMode: .edit,
        )

        XCTAssertEqual(
            exactFolderState.candidateSelectionIntent(for: "/Users/me/Documents/Secrets"),
            .replace(oldPath: "/Users/me/Documents", newPath: "/Users/me/Documents/Secrets"),
        )
    }

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

    func testApplyCandidateDisambiguationPolicySetsDistinctSecondaryTextForDuplicateNames() {
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
        XCTAssertEqual(Set(result.compactMap(\.secondaryText)).count, 2)
        XCTAssertEqual(result[0].secondaryText, result[0].locationIdentifier)
        XCTAssertEqual(result[1].secondaryText, result[1].locationIdentifier)
    }

    func testSameNameCandidatesExposeDistinctLocationMetadata() {
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

        XCTAssertEqual(Set(result.map(\.locationIdentifier)), ["/Users/me/Work", "/Users/me/Personal"])
        XCTAssertEqual(Set(result.compactMap(\.secondaryText)), ["/Users/me/Work", "/Users/me/Personal"])
    }

    func testDefaultAndSearchCandidatesShareLocationMetadataContract() {
        let defaultCandidates = makeDefaultScopeEditorCandidates(
            favorites: [],
            backHistory: ["/Users/me/Work/Docs"],
            entryLoadingClient: makeEntryLoadingClient(),
        )

        let searchItems = ComposerScopeUtils.applyCandidateDisambiguationPolicy([
            ComposerScopeUtils.DirectoryItem(
                id: "/Users/me/Work/Docs",
                path: "/Users/me/Work/Docs",
                name: "Docs",
                iconName: "folder",
                locationIdentifier: "/Users/me/Work",
            ),
        ])
        let searchCandidate = ComposerScopeEditorCandidateItem(
            path: searchItems[0].path,
            name: searchItems[0].name,
            iconName: searchItems[0].iconName,
            locationIdentifier: searchItems[0].locationIdentifier,
            secondaryText: searchItems[0].secondaryText,
        )

        XCTAssertEqual(defaultCandidates.first?.locationIdentifier, searchCandidate.locationIdentifier)
        XCTAssertEqual(defaultCandidates.first?.secondaryText, searchCandidate.secondaryText)
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
        XCTAssertEqual(candidates?.map(\.secondaryText), ["/Users/me/Documents", "/Users/me/Archive"])
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
            candidateItems: ComposerScopeUtils.applyCandidateDisambiguationPolicy([
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
            ]).map { item in
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

    func testMakeDefaultScopeEditorCandidatesAppliesDisambiguationPolicyToDuplicateNamesOnly() {
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
        XCTAssertEqual(Set(duplicateCandidates.compactMap(\.secondaryText)), [
            "/Users/me/Personal",
            "/Users/me/Work",
        ])

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
