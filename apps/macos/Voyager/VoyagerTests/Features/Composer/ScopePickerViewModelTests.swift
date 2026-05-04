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

    func testSectionsAssignOverlappingExceptionToLongestOwningBase() {
        let state = ComposerScopeEditorState(
            selection: .explicit(
                bases: [
                    ComposerScopeBase(path: "/Users/me"),
                    ComposerScopeBase(path: "/Users/me/Documents"),
                    ComposerScopeBase(path: "/Users/me/Desktop"),
                ],
                exceptions: [
                    ComposerScopeException(path: "/Users/me/Documents/Secrets"),
                    ComposerScopeException(path: "/Users/me/Desktop/Scratch"),
                    ComposerScopeException(path: "/tmp/Detached"),
                ],
            ),
            listState: .defaultCandidates,
            isPresented: true,
            queryText: "",
            candidateItems: [],
        )

        let sections = state.sections()
        let currentItemIDs = sections[0].items.map(\.id)

        XCTAssertEqual(currentItemIDs, [
            "current-/Users/me",
            "current-/Users/me/Documents",
            "exception-/Users/me/Documents-/Users/me/Documents/Secrets",
            "current-/Users/me/Desktop",
            "exception-/Users/me/Desktop-/Users/me/Desktop/Scratch",
        ])
        XCTAssertTrue(currentItemIDs.contains("exception-/Users/me/Documents-/Users/me/Documents/Secrets"))
        XCTAssertFalse(currentItemIDs.contains("exception-/Users/me-/Users/me/Documents/Secrets"))
        XCTAssertFalse(currentItemIDs.contains("exception-/Users/me-/tmp/Detached"))
        XCTAssertFalse(currentItemIDs.contains("exception-/Users/me/Documents-/tmp/Detached"))

        guard case let .currentScope(rootBase) = sections[0].items[0] else {
            return XCTFail("expected root current scope item")
        }
        XCTAssertEqual(rootBase.exceptionCount, 0)

        guard case let .currentScope(documentsBase) = sections[0].items[1] else {
            return XCTFail("expected documents current scope item")
        }
        XCTAssertEqual(documentsBase.exceptionCount, 1)

        guard case let .currentScope(desktopBase) = sections[0].items[3] else {
            return XCTFail("expected desktop current scope item")
        }
        XCTAssertEqual(desktopBase.exceptionCount, 1)
    }

    func testCanonicalSelectionPrunesNonDescendantExceptionsFromSections() {
        let selection = ComposerScopeSelection.fromCanonicalScopes(
            bases: ["/Users/me/Documents"],
            exceptions: [
                "/Users/me/Documents/Secrets",
                "/tmp/Detached",
            ],
            includeSubfolders: true,
        )
        let state = ComposerScopeEditorState(
            selection: selection,
            listState: .defaultCandidates,
            isPresented: true,
            queryText: "",
            candidateItems: [],
        )

        XCTAssertEqual(selection.exceptions.map(\.path), ["/Users/me/Documents/Secrets"])
        XCTAssertFalse(selection.exceptions.map(\.path).contains("/tmp/Detached"))

        let sections = state.sections()
        let itemIDs = sections.flatMap(\.items).map(\.id)

        XCTAssertFalse(itemIDs.contains("exception-/Users/me/Documents-/tmp/Detached"))
        XCTAssertFalse(itemIDs.contains { $0.contains("/tmp/Detached") })
    }

    func testSectionsKeepInlineExceptionsVisibleDuringScopeApplyState() {
        let selection: ComposerScopeSelection = .explicit(
            bases: [ComposerScopeBase(path: "/Users/me/Documents")],
            exceptions: [
                ComposerScopeException(path: "/Users/me/Documents/Secrets"),
            ],
        )
        let state = ComposerScopeEditorState(
            selection: selection,
            committedSelection: .rootOnly,
            listState: .defaultCandidates,
            isPresented: true,
            queryText: "",
            candidateItems: [],
        )

        XCTAssertTrue(state.hasPendingScopeRuleChanges)

        let sections = state.sections()

        XCTAssertEqual(sections.map(\.kind.id), ["current-scopes", "addable-default"])
        XCTAssertEqual(sections[0].items.map(\.id), [
            "current-/Users/me/Documents",
            "exception-/Users/me/Documents-/Users/me/Documents/Secrets",
        ])

        guard case let .currentScope(baseItem) = sections[0].items[0] else {
            return XCTFail("expected current scope item")
        }
        XCTAssertEqual(baseItem.base.path, "/Users/me/Documents")
        XCTAssertEqual(baseItem.exceptionCount, 1)

        guard case let .exceptionScope(exceptionItem) = sections[0].items[1] else {
            return XCTFail("expected inline exception item")
        }
        XCTAssertEqual(exceptionItem.path, "/Users/me/Documents/Secrets")
        XCTAssertEqual(exceptionItem.owningBasePath, "/Users/me/Documents")
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

    func testScopeFeedbackSnapshotEqualityDependsOnScopeMeaningOnly() {
        let baseSelection: ComposerScopeSelection = .explicit(
            bases: [ComposerScopeBase(path: "/Users/me/Documents")],
            exceptions: [ComposerScopeException(path: "/Users/me/Documents/Secrets")],
        )

        let canonicalSnapshot = ComposerScopeSnapshot(
            scopeSelection: baseSelection,
            includeSubfolders: true,
        )
        let sameMeaningDifferentNoiseSnapshot = ComposerScopeSnapshot(
            scopeSelection: baseSelection,
            includeSubfolders: true,
        )
        let differentIncludeSubfoldersSnapshot = ComposerScopeSnapshot(
            scopeSelection: baseSelection,
            includeSubfolders: false,
        )

        XCTAssertEqual(canonicalSnapshot, sameMeaningDifferentNoiseSnapshot)
        XCTAssertNotEqual(canonicalSnapshot, differentIncludeSubfoldersSnapshot)
    }

    func testScopeFeedbackSnapshotChangesWithBaseAndExceptionMeaning() {
        let rootOnlySnapshot = ComposerScopeSnapshot(
            scopeSelection: .rootOnly,
            includeSubfolders: true,
        )
        let explicitBaseSnapshot = ComposerScopeSnapshot(
            scopeSelection: .explicit(
                bases: [ComposerScopeBase(path: "/Users/me/Documents")],
                exceptions: [],
            ),
            includeSubfolders: true,
        )
        let explicitExceptionSnapshot = ComposerScopeSnapshot(
            scopeSelection: .explicit(
                bases: [ComposerScopeBase(path: "/Users/me/Documents")],
                exceptions: [ComposerScopeException(path: "/Users/me/Documents/Secrets")],
            ),
            includeSubfolders: true,
        )

        XCTAssertNotEqual(rootOnlySnapshot, explicitBaseSnapshot)
        XCTAssertNotEqual(explicitBaseSnapshot, explicitExceptionSnapshot)
        XCTAssertEqual(
            explicitExceptionSnapshot,
            ComposerScopeSnapshot(
                scopeSelection: .explicit(
                    bases: [ComposerScopeBase(path: "/Users/me/Documents")],
                    exceptions: [ComposerScopeException(path: "/Users/me/Documents/Secrets")],
                ),
                includeSubfolders: true,
            ),
        )
    }
}
