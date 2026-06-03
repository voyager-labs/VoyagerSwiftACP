import Foundation
@testable import Voyager
import XCTest

@MainActor
final class ScopePickerTreeProjectionTests: XCTestCase {
    func testTreeRowContractPreservesCandidateMetadata() {
        let row = ComposerScopeTreeRow(
            path: "/Users/me/Documents/",
            depth: 2,
            displayName: "Documents",
            iconName: "folder.fill",
            locationIdentifier: "sidebar-documents",
            secondaryText: "iCloud Drive",
            kind: .candidate,
            visualState: .none,
            ruleSource: .inherited(sourcePath: "/Users/me"),
            availableActions: [.include, .exclude],
            owningBasePath: "/Users/me",
        )
        XCTAssertEqual(row.path, "/Users/me/Documents/")
        XCTAssertEqual(row.depth, 2)
        XCTAssertEqual(row.displayName, "Documents")
        XCTAssertEqual(row.iconName, "folder.fill")
        XCTAssertEqual(row.locationIdentifier, "sidebar-documents")
        XCTAssertEqual(row.secondaryText, "iCloud Drive")
        XCTAssertEqual(row.kind, .candidate)
        XCTAssertEqual(row.visualState, .none)
        XCTAssertEqual(row.ruleSource, .inherited(sourcePath: "/Users/me"))
        XCTAssertEqual(row.availableActions, [.include, .exclude])
        XCTAssertEqual(row.owningBasePath, "/Users/me")
        XCTAssertEqual(row.id, "candidate-/Users/me/Documents")
    }

    func testRootOnlyTreeRowsStartWithSyntheticThisMacAndCandidatesRemainAddable() {
        let state = makeTreeState(
            selection: .rootOnly,
            candidateItems: [
                .init(path: "/Users/me/Documents", name: "Documents", iconName: "folder"),
                .init(path: "/Users/me/Downloads", name: "Downloads", iconName: "folder"),
            ],
        )
        let rows = state.treeRows(neighborhoodSeedItems: [])
        XCTAssertEqual(rows.map(\.path), ["/", "/Users/me/Documents", "/Users/me/Downloads"])
        XCTAssertEqual(rows[0].displayName, "This Mac")
        XCTAssertEqual(rows[0].kind, .root)
        XCTAssertEqual(rows[0].visualState, .included)
        XCTAssertEqual(rows[0].ruleSource, .none)
        XCTAssertEqual(rows[0].availableActions, [])
        XCTAssertEqual(rows[0].depth, 0)
        XCTAssertNil(rows[0].owningBasePath)
        XCTAssertEqual(rows[1].kind, .candidate)
        XCTAssertEqual(rows[1].visualState, .none)
        XCTAssertEqual(rows[1].ruleSource, .none)
        XCTAssertEqual(rows[1].availableActions, [.include])
        XCTAssertNil(rows[1].owningBasePath)
        XCTAssertEqual(rows[2].kind, .candidate)
        XCTAssertEqual(rows[2].visualState, .none)
        XCTAssertEqual(rows[2].availableActions, [.include])
    }

    func testTreeRowsApplySourceOrderAndDedupePriority() {
        let rows = makeDedupeProjectionState().treeRows(neighborhoodSeedItems: makeDedupeNeighborhood())
        XCTAssertEqual(rows.map(\.path), [
            "/Users/me",
            "/Users/me/Documents",
            "/Users/me/Documents/Secret",
            "/Users/me/Documents/Reports",
            "/Users/me/Downloads",
            "/Users/me/Desktop",
        ])
        XCTAssertEqual(rows[4].locationIdentifier, "canonical-location")
        XCTAssertEqual(rows[4].secondaryText, "Canonical")
        XCTAssertEqual(rows[4].depth, 0)
        XCTAssertNil(rows[5].locationIdentifier)
        XCTAssertEqual(rows[5].depth, 2)
    }

    func testTreeRowsDeriveDepthAndOwningBasePath() {
        let state = makeTreeState(
            selection: .explicit(
                bases: [
                    ComposerScopeBase(path: "/Users/me"),
                    ComposerScopeBase(path: "/Users/me/Documents"),
                ],
                exceptions: [
                    ComposerScopeException(path: "/Users/me/Documents/Secret"),
                ],
            ),
            candidateItems: [
                .init(path: "/Users/me/Documents/Reports", name: "Reports", iconName: "folder"),
            ],
        )
        let neighborhood = [
            ComposerScopeTreeSeedItem(
                path: "/Users/me/Documents/Child",
                name: "Child",
                iconName: "folder",
                depth: 3,
            ),
            ComposerScopeTreeSeedItem(
                path: "/Users/me/Documents/Secret/Deep",
                name: "Deep",
                iconName: "folder",
                depth: 4,
            ),
        ]
        let rowsByPath = treeRowsByPath(for: state.treeRows(neighborhoodSeedItems: neighborhood))
        XCTAssertEqual(rowsByPath["/Users/me"]?.depth, 0)
        XCTAssertNil(rowsByPath["/Users/me"]?.owningBasePath)
        XCTAssertEqual(rowsByPath["/Users/me/Documents"]?.depth, 0)
        XCTAssertNil(rowsByPath["/Users/me/Documents"]?.owningBasePath)
        XCTAssertEqual(rowsByPath["/Users/me/Documents/Secret"]?.depth, 1)
        XCTAssertEqual(rowsByPath["/Users/me/Documents/Secret"]?.owningBasePath, "/Users/me/Documents")
        XCTAssertEqual(rowsByPath["/Users/me/Documents/Reports"]?.depth, 0)
        XCTAssertEqual(rowsByPath["/Users/me/Documents/Reports"]?.owningBasePath, "/Users/me/Documents")
        XCTAssertEqual(rowsByPath["/Users/me/Documents/Child"]?.depth, 3)
        XCTAssertEqual(rowsByPath["/Users/me/Documents/Child"]?.owningBasePath, "/Users/me/Documents")
        XCTAssertEqual(rowsByPath["/Users/me/Documents/Secret/Deep"]?.depth, 4)
        XCTAssertEqual(rowsByPath["/Users/me/Documents/Secret/Deep"]?.owningBasePath, "/Users/me/Documents")
    }

    func testTreeRowIDUsesKindAndNormalizedPath() {
        XCTAssertEqual(makeNormalizedIDRows().map(\.id), [
            "root-/",
            "base-/Users/me/Documents",
            "exception-/Users/me/Documents/Secret",
            "candidate-/Users/me/Downloads",
        ])
    }

    func testClosestAncestorTieBreaksLexicographicallyForDefensiveDeterminism() {
        let selected = ComposerScopeTreeProjection.selectMostSpecificPath([
            "/tmp/zeta",
            "/tmp/able",
            "/tmp/middle",
        ])
        XCTAssertEqual(selected, "/tmp/able")
    }

    func testTreeRowsMarkDirectIncludedExcludedAndNone() {
        let state = makeTreeState(
            selection: .explicit(
                bases: [ComposerScopeBase(path: "/Users/me/Documents")],
                exceptions: [ComposerScopeException(path: "/Users/me/Documents/Secret")],
            ),
            candidateItems: [
                .init(path: "/Users/me/Documents/Secret", name: "Secret", iconName: "folder"),
                .init(path: "/Users/me/Downloads", name: "Downloads", iconName: "folder"),
            ],
        )
        let rowsByPath = treeRowsByPath(for: state.treeRows(neighborhoodSeedItems: []))
        XCTAssertEqual(rowsByPath["/Users/me/Documents"]?.visualState, .included)
        XCTAssertEqual(rowsByPath["/Users/me/Documents"]?.ruleSource, .direct)
        XCTAssertEqual(rowsByPath["/Users/me/Documents"]?.availableActions, [.clearDirectRule])
        XCTAssertEqual(rowsByPath["/Users/me/Documents/Secret"]?.visualState, .excluded)
        XCTAssertEqual(rowsByPath["/Users/me/Documents/Secret"]?.ruleSource, .direct)
        XCTAssertEqual(rowsByPath["/Users/me/Documents/Secret"]?.availableActions, [.clearDirectRule])
        XCTAssertEqual(rowsByPath["/Users/me/Documents/Secret"]?.owningBasePath, "/Users/me/Documents")
        XCTAssertEqual(rowsByPath["/Users/me/Downloads"]?.visualState, .none)
        XCTAssertEqual(rowsByPath["/Users/me/Downloads"]?.ruleSource, .none)
        XCTAssertEqual(rowsByPath["/Users/me/Downloads"]?.availableActions, [.include])
        XCTAssertNil(rowsByPath["/Users/me/Downloads"]?.owningBasePath)
    }

    func testTreeRowsPreferClosestInheritedRule() {
        let state = makeTreeState(
            selection: .explicit(
                bases: [
                    ComposerScopeBase(path: "/Users/me"),
                    ComposerScopeBase(path: "/Users/me/Documents"),
                ],
                exceptions: [
                    ComposerScopeException(path: "/Users/me/Secret"),
                    ComposerScopeException(path: "/Users/me/Documents/Secret"),
                ],
            ),
            candidateItems: [
                .init(path: "/Users/me/Documents/Reports", name: "Reports", iconName: "folder"),
                .init(path: "/Users/me/Documents/Secret/Deep", name: "Deep", iconName: "folder"),
                .init(path: "/Users/me/Secret/Other", name: "Other", iconName: "folder"),
            ],
        )
        let rowsByPath = treeRowsByPath(for: state.treeRows(neighborhoodSeedItems: []))
        XCTAssertEqual(rowsByPath["/Users/me/Documents/Reports"]?.visualState, .included)
        XCTAssertEqual(
            rowsByPath["/Users/me/Documents/Reports"]?.ruleSource,
            .inherited(sourcePath: "/Users/me/Documents"),
        )
        XCTAssertEqual(rowsByPath["/Users/me/Documents/Reports"]?.availableActions, [.exclude])
        XCTAssertEqual(rowsByPath["/Users/me/Documents/Reports"]?.owningBasePath, "/Users/me/Documents")
        XCTAssertEqual(rowsByPath["/Users/me/Documents/Secret/Deep"]?.visualState, .excluded)
        XCTAssertEqual(
            rowsByPath["/Users/me/Documents/Secret/Deep"]?.ruleSource,
            .inherited(sourcePath: "/Users/me/Documents/Secret"),
        )
        XCTAssertEqual(rowsByPath["/Users/me/Documents/Secret/Deep"]?.availableActions, [])
        XCTAssertEqual(rowsByPath["/Users/me/Documents/Secret/Deep"]?.owningBasePath, "/Users/me/Documents")
        XCTAssertEqual(rowsByPath["/Users/me/Secret/Other"]?.visualState, .excluded)
        XCTAssertEqual(rowsByPath["/Users/me/Secret/Other"]?.ruleSource, .inherited(sourcePath: "/Users/me/Secret"))
        XCTAssertEqual(rowsByPath["/Users/me/Secret/Other"]?.owningBasePath, "/Users/me")
    }

    func testExactFolderModeDoesNotInheritIncludedState() {
        var state = makeTreeState(
            selection: .explicit(
                bases: [ComposerScopeBase(path: "/Users/me/Documents")],
                exceptions: [],
            ),
            candidateItems: [
                .init(path: "/Users/me/Documents/Subfolder", name: "Subfolder", iconName: "folder"),
            ],
        )
        state.includeSubfolders = false
        let rowsByPath = treeRowsByPath(for: state.treeRows(neighborhoodSeedItems: []))
        XCTAssertEqual(rowsByPath["/Users/me/Documents/Subfolder"]?.visualState, .none)
        XCTAssertEqual(rowsByPath["/Users/me/Documents/Subfolder"]?.ruleSource, .none)
        XCTAssertEqual(rowsByPath["/Users/me/Documents/Subfolder"]?.availableActions, [.include])
        XCTAssertNil(rowsByPath["/Users/me/Documents/Subfolder"]?.owningBasePath)
    }

    func testTreeRowsDirectBaseOutranksTransientNeighborhoodCurrentSeed() {
        let state = makeTreeState(
            selection: .explicit(
                bases: [ComposerScopeBase(path: "/Users/me/Documents")],
                exceptions: [],
            ),
            candidateItems: [],
        )
        let rows = state.treeRows(neighborhoodSeedItems: [
            ComposerScopeTreeSeedItem(
                path: "/Users/me/Documents",
                name: "Documents Seed",
                iconName: "folder.badge.plus",
                locationIdentifier: "seed-location",
                secondaryText: "Transient",
            ),
        ])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].path, "/Users/me/Documents")
        XCTAssertEqual(rows[0].kind, .base)
        XCTAssertNil(rows[0].locationIdentifier)
        XCTAssertNil(rows[0].secondaryText)
    }
}

@MainActor
extension ScopePickerTreeProjectionTests {
    func testTreeActionIntentMapsToExistingScopeActions() {
        let state = makeTreeState(
            selection: .explicit(
                bases: [ComposerScopeBase(path: "/Users/me/Documents")],
                exceptions: [ComposerScopeException(path: "/Users/me/Documents/Secret")],
            ),
            candidateItems: [
                .init(path: "/Users/me/Downloads", name: "Downloads", iconName: "folder"),
            ],
        )
        XCTAssertEqual(
            state.treeActionIntent(rowPath: "/Users/me/Downloads", action: .include),
            .addBase(path: "/Users/me/Downloads"),
        )
        XCTAssertEqual(
            state.treeActionIntent(rowPath: "/Users/me/Downloads", action: .exclude),
            .exclude(path: "/Users/me/Downloads"),
        )
        XCTAssertEqual(
            state.treeActionIntent(rowPath: "/Users/me/Documents", action: .clearDirectRule),
            .removeBase(path: "/Users/me/Documents"),
        )
        XCTAssertEqual(
            state.treeActionIntent(rowPath: "/Users/me/Documents/Secret", action: .clearDirectRule),
            .restoreException(path: "/Users/me/Documents/Secret"),
        )
    }

    func testInheritedRowsDoNotExposeClearDirectRule() {
        let state = makeTreeState(
            selection: .explicit(
                bases: [ComposerScopeBase(path: "/Users/me/Documents")],
                exceptions: [ComposerScopeException(path: "/Users/me/Documents/Secret")],
            ),
            candidateItems: [
                .init(path: "/Users/me/Documents/Subfolder", name: "Subfolder", iconName: "folder"),
                .init(path: "/Users/me/Documents/Secret/Deep", name: "Deep", iconName: "folder"),
            ],
        )
        let rowsByPath = treeRowsByPath(for: state.treeRows(neighborhoodSeedItems: []))
        XCTAssertEqual(rowsByPath["/Users/me/Documents/Subfolder"]?.availableActions, [.exclude])
        XCTAssertEqual(rowsByPath["/Users/me/Documents/Secret/Deep"]?.availableActions, [])
        XCTAssertEqual(
            state.treeActionIntent(rowPath: "/Users/me/Documents/Subfolder", action: .clearDirectRule),
            .none,
        )
        XCTAssertEqual(
            state.treeActionIntent(rowPath: "/Users/me/Documents/Secret/Deep", action: .clearDirectRule),
            .none,
        )
        XCTAssertEqual(state.treeActionIntent(rowPath: "/Users/me/Documents/Secret/Deep", action: .include), .none)
        XCTAssertEqual(state.treeActionIntent(rowPath: "/Users/me/Documents/Secret/Deep", action: .exclude), .none)
    }

    func testClearDirectExceptionFallsBackToInheritedExcludedWhenAncestorExceptionExists() {
        let directState = makeTreeState(
            selection: .explicit(
                bases: [ComposerScopeBase(path: "/Users/me/Documents")],
                exceptions: [
                    ComposerScopeException(path: "/Users/me/Documents/Secret"),
                    ComposerScopeException(path: "/Users/me/Documents/Secret/Child"),
                ],
            ),
            candidateItems: [
                .init(path: "/Users/me/Documents/Secret/Child", name: "Child", iconName: "folder"),
            ],
        )
        let fallbackState = makeTreeState(
            selection: .explicit(
                bases: [ComposerScopeBase(path: "/Users/me/Documents")],
                exceptions: [ComposerScopeException(path: "/Users/me/Documents/Secret")],
            ),
            candidateItems: [
                .init(path: "/Users/me/Documents/Secret/Child", name: "Child", iconName: "folder"),
            ],
        )
        let fallbackRows = treeRowsByPath(for: fallbackState.treeRows(neighborhoodSeedItems: []))
        XCTAssertEqual(
            directState.treeActionIntent(rowPath: "/Users/me/Documents/Secret/Child", action: .clearDirectRule),
            .restoreException(path: "/Users/me/Documents/Secret/Child"),
        )
        XCTAssertEqual(fallbackRows["/Users/me/Documents/Secret/Child"]?.visualState, .excluded)
        XCTAssertEqual(
            fallbackRows["/Users/me/Documents/Secret/Child"]?.ruleSource,
            .inherited(sourcePath: "/Users/me/Documents/Secret"),
        )
        XCTAssertEqual(fallbackRows["/Users/me/Documents/Secret/Child"]?.availableActions, [])
        XCTAssertEqual(
            fallbackState.treeActionIntent(rowPath: "/Users/me/Documents/Secret/Child", action: .clearDirectRule),
            .none,
        )
    }

    func testNeighborhoodOnlyPathStillMapsTreeActionIntentFromInheritedIncludedState() {
        let state = makeTreeState(
            selection: .explicit(
                bases: [ComposerScopeBase(path: "/Users/me/Documents")],
                exceptions: [],
            ),
            candidateItems: [],
        )
        let neighborhoodRows = state.treeRows(neighborhoodSeedItems: [
            ComposerScopeTreeSeedItem(
                path: "/Users/me/Documents/Reports",
                name: "Reports",
                iconName: "folder",
            ),
        ])
        let rowsByPath = treeRowsByPath(for: neighborhoodRows)
        XCTAssertEqual(rowsByPath["/Users/me/Documents/Reports"]?.visualState, .included)
        XCTAssertEqual(
            rowsByPath["/Users/me/Documents/Reports"]?.ruleSource,
            .inherited(sourcePath: "/Users/me/Documents"),
        )
        XCTAssertEqual(rowsByPath["/Users/me/Documents/Reports"]?.availableActions, [.exclude])
        XCTAssertEqual(
            state.treeActionIntent(rowPath: "/Users/me/Documents/Reports", action: .exclude),
            .exclude(path: "/Users/me/Documents/Reports"),
        )
        XCTAssertEqual(
            state.treeActionIntent(rowPath: "/Users/me/Documents/Reports", action: .include),
            .none,
        )
    }
}

@MainActor
private func makeTreeState(
    selection: ComposerScopeSelection,
    candidateItems: [ComposerScopeEditorCandidateItem],
    listState: ComposerScopeEditorListState = .defaultCandidates,
) -> ComposerScopeEditorState {
    ComposerScopeEditorState(
        selection: selection,
        listState: listState,
        isPresented: true,
        queryText: "",
        candidateItems: candidateItems,
    )
}

@MainActor
private func makeDedupeProjectionState() -> ComposerScopeEditorState {
    makeTreeState(
        selection: .explicit(
            bases: [
                ComposerScopeBase(path: "/Users/me"),
                ComposerScopeBase(path: "/Users/me/Documents"),
            ],
            exceptions: [
                ComposerScopeException(path: "/Users/me/Documents/Secret"),
            ],
        ),
        candidateItems: [
            .init(path: "/Users/me", name: "Me", iconName: "folder"),
            .init(path: "/Users/me/Documents/Secret", name: "Secret", iconName: "folder"),
            .init(path: "/Users/me/Documents/Reports", name: "Reports", iconName: "folder"),
            .init(
                path: "/Users/me/Downloads",
                name: "Downloads",
                iconName: "folder",
                locationIdentifier: "canonical-location",
                secondaryText: "Canonical",
            ),
        ],
    )
}

@MainActor
private func makeDedupeNeighborhood() -> [ComposerScopeTreeSeedItem] {
    [
        ComposerScopeTreeSeedItem(
            path: "/Users/me/Downloads",
            name: "Downloads Seed",
            iconName: "folder.badge.plus",
            locationIdentifier: "seed-location",
            secondaryText: "Transient",
            depth: 3,
        ),
        ComposerScopeTreeSeedItem(
            path: "/Users/me/Desktop",
            name: "Desktop",
            iconName: "folder",
            depth: 2,
        ),
    ]
}

@MainActor
private func makeNormalizedIDRows() -> [ComposerScopeTreeRow] {
    [
        makeIDFixtureRow(path: "/", depth: 0, kind: .root, visualState: .included, ruleSource: .none),
        makeIDFixtureRow(
            path: "/Users/me/Documents/",
            depth: 0,
            kind: .base,
            visualState: .included,
            ruleSource: .direct,
            availableActions: [.clearDirectRule],
        ),
        makeIDFixtureRow(
            path: "/Users/me/Documents/Secret/",
            depth: 1,
            kind: .exception,
            visualState: .excluded,
            ruleSource: .direct,
            availableActions: [.clearDirectRule],
            owningBasePath: "/Users/me/Documents",
        ),
        makeIDFixtureRow(
            path: "/Users/me/Downloads/",
            depth: 0,
            kind: .candidate,
            visualState: .none,
            ruleSource: .none,
            availableActions: [.include],
        ),
    ]
}

@MainActor
private func makeIDFixtureRow(
    path: String,
    depth: Int,
    kind: ComposerScopeTreeRowKind,
    visualState: ComposerScopeTreeRowVisualState,
    ruleSource: ComposerScopeTreeRowRuleSource,
    availableActions: [ComposerScopeTreeRowAvailableAction] = [],
    owningBasePath: String? = nil,
) -> ComposerScopeTreeRow {
    let normalizedPath = ComposerScopeUtils.normalizeScopePath(path)
    let displayName = normalizedPath == "/" ? "This Mac" : (normalizedPath as NSString).lastPathComponent

    return ComposerScopeTreeRow(
        path: path,
        depth: depth,
        displayName: displayName,
        iconName: "folder",
        locationIdentifier: nil,
        secondaryText: nil,
        kind: kind,
        visualState: visualState,
        ruleSource: ruleSource,
        availableActions: availableActions,
        owningBasePath: owningBasePath,
    )
}

@MainActor
private func treeRowsByPath(for rows: [ComposerScopeTreeRow]) -> [String: ComposerScopeTreeRow] {
    Dictionary(uniqueKeysWithValues: rows.map { ($0.path, $0) })
}
