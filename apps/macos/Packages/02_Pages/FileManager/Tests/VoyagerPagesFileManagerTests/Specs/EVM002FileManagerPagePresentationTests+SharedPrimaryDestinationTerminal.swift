import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
@testable import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerWidgetsEntryViewLayout
import XCTest

extension EVM002FileManagerPagePresentationTests {
    /// EVM-002-command_external_refresh_correlation: shared primary terminal은 nil-owner additional pair도 종결한다.
    /// - 검증 내용: empty destination batch로 deferred replacement를 만든 뒤 accepted coreFinished를 처리한다.
    /// - 사전 조건: primary와 additional이 expanded C를 공유하고 source D hold가 pre-arm돼 있다.
    /// - 기대 결과: transition과 destination/source replacement가 닫히며 retained source children은 중복 없이 유지된다.
    func testSharedPrimaryDestinationTerminalResolvesNilOwnerAdditionalPair() async {
        let fixture = makeSharedPrimaryTerminalFixture()
        await startSharedPrimaryTerminalFixture(fixture)

        await fixture.store.send(folderResponse(
            fixture.destination.id,
            generation: 4,
            .event(.coreBatch(items: [], batchIndex: 0)),
        ))
        XCTAssertNotNil(fixture.store.state.entryViewLayout.hierarchy.deferredFolderReplacement(
            folderID: fixture.destination.id,
        ))
        await fixture.store.send(folderResponse(
            fixture.destination.id,
            generation: 4,
            .event(.coreFinished(batchCount: 1)),
        ))

        XCTAssertNil(fixture.store.state.pendingIdentityTransition)
        XCTAssertNil(fixture.store.state.entryViewLayout.hierarchy.deferredFolderReplacement(
            folderID: fixture.destination.id,
        ))
        XCTAssertNil(fixture.store.state.entryViewLayout.hierarchy.deferredFolderReplacement(
            folderID: fixture.source.id,
        ))
        XCTAssertEqual(
            fixture.store.state.entryViewLayout.hierarchy.nodesByID[fixture.source.id]?.folder.children,
            [fixture.beforePrimary, fixture.beforeAdditional],
        )
        XCTAssertEqual(
            fixture.store.state.entryViewLayout.hierarchy.nodesByID[fixture.destination.id]?.folder.children,
            [],
        )
        await fixture.store.skipInFlightEffects()
    }

    /// EVM-002-command_external_refresh_correlation: shared primary failure도 nil-owner additional pair를 종결한다.
    /// - 검증 내용: partial empty staging 뒤 accepted folder failure가 transition과 모든 replacement를 정리한다.
    /// - 사전 조건: source와 destination 모두 retained complete snapshot에서 generation 4를 로드 중이다.
    /// - 기대 결과: 실패 staging은 retained destination을 덮지 않고 source hold와 transition만 닫힌다.
    func testSharedPrimaryDestinationFailureResolvesNilOwnerAdditionalPair() async {
        let fixture = makeSharedPrimaryTerminalFixture()
        await startSharedPrimaryTerminalFixture(fixture)

        await fixture.store.send(folderResponse(
            fixture.destination.id,
            generation: 4,
            .event(.coreBatch(items: [], batchIndex: 0)),
        ))
        await fixture.store.send(folderResponse(
            fixture.destination.id,
            generation: 4,
            .failed(.permissionDenied),
        ))

        XCTAssertNil(fixture.store.state.pendingIdentityTransition)
        XCTAssertNil(fixture.store.state.entryViewLayout.hierarchy.deferredFolderReplacement(
            folderID: fixture.destination.id,
        ))
        XCTAssertNil(fixture.store.state.entryViewLayout.hierarchy.deferredFolderReplacement(
            folderID: fixture.source.id,
        ))
        XCTAssertEqual(
            fixture.store.state.entryViewLayout.hierarchy.nodesByID[fixture.destination.id]?.folder.children,
            [fixture.oldDestinationChild],
        )
        XCTAssertEqual(
            fixture.store.state.entryViewLayout.hierarchy.nodesByID[fixture.source.id]?.folder.children,
            [fixture.beforePrimary, fixture.beforeAdditional],
        )
        await fixture.store.skipInFlightEffects()
    }

    /// EVM-002-command_external_refresh_correlation: stale shared-primary terminal은 nil-owner pair를 건드리지 않는다.
    /// - 검증 내용: generation 3 coreFinished를 거부한 뒤 generation 4 terminal로 동일 transition을 정리한다.
    /// - 사전 조건: entryActionCompleted invalidation이 C owner를 generation 4로 rebase했다.
    /// - 기대 결과: stale 뒤 pair/hold 유지, current terminal 뒤 transition과 hold가 한 번만 닫힌다.
    func testStaleSharedPrimaryDestinationTerminalDoesNotResolveNilOwnerAdditionalPair() async {
        let fixture = makeSharedPrimaryTerminalFixture()
        await startSharedPrimaryTerminalFixture(fixture)

        await fixture.store.send(folderResponse(
            fixture.destination.id,
            generation: 3,
            .event(.coreFinished(batchCount: 0)),
        ))
        XCTAssertEqual(fixture.store.state.pendingIdentityTransition?.additionalMoves.first?.migrated, false)
        XCTAssertNotNil(fixture.store.state.entryViewLayout.hierarchy.deferredFolderReplacement(
            folderID: fixture.source.id,
        ))

        await fixture.store.send(folderResponse(
            fixture.destination.id,
            generation: 4,
            .event(.coreBatch(items: [], batchIndex: 0)),
        ))
        await fixture.store.send(folderResponse(
            fixture.destination.id,
            generation: 4,
            .event(.coreFinished(batchCount: 1)),
        ))
        XCTAssertNil(fixture.store.state.pendingIdentityTransition)
        XCTAssertNil(fixture.store.state.entryViewLayout.hierarchy.deferredFolderReplacement(
            folderID: fixture.source.id,
        ))
        await fixture.store.skipInFlightEffects()
    }

    /// EVM-002-command_external_refresh_correlation: additional destination collapse는 pair와 source hold를 종결한다.
    /// - 검증 내용: primary A migration 뒤 pending C folder를 collapse하고 transition/source replacement를 검사한다.
    /// - 사전 조건: entryActionCompleted invalidation이 source D와 destinations A/C를 generation 4로 시작했다.
    /// - 기대 결과: C response 없이도 pair가 terminalized되고 primary selection과 retained source snapshot이 유지된다.
    func testAdditionalDestinationCollapseSettlesPairAndSourceHold() async {
        let source = EntryModel.temporaryFolder(id: "/root/D", name: "D")
        let primaryDestination = EntryModel.temporaryFolder(id: "/root/A", name: "A")
        let additionalDestination = EntryModel.temporaryFolder(id: "/root/C", name: "C")
        let beforePrimary = EntryModel.temporaryFolder(id: "/root/D/p", name: "p")
        let beforeAdditional = EntryModel.temporaryFolder(id: "/root/D/q", name: "q")
        let afterPrimary = EntryModel.temporaryFolder(id: "/root/A/p", name: "p")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath("/root")
        state.entryViewLayout.entries = [source, primaryDestination, additionalDestination]
        state.entryViewLayout.hierarchy = .init(rootPath: "/root")
        for (folder, children) in [
            (source, [beforePrimary, beforeAdditional]),
            (primaryDestination, []),
            (additionalDestination, []),
        ] {
            state.entryViewLayout.hierarchy.nodesByID[folder.id] = .init(
                children: children, loadPhase: .loaded, generation: 3, coreFinished: true,
            )
        }
        state.entryViewLayout.hierarchy.setExpandedIDs([source.id, primaryDestination.id, additionalDestination.id])
        state.entryViewLayout.selectedIds = [beforePrimary.id, beforeAdditional.id]
        let record = EntryActionRecord(
            operationKind: .pasteFileMove,
            targets: [
                .init(beforePath: beforePrimary.id, afterPath: afterPrimary.id),
                .init(beforePath: beforeAdditional.id, afterPath: "/root/C/q"),
            ],
        )
        let store = makeIdentityTransitionStore(state)

        await store.send(.entryViewLayout(.entryOperations(.lifecycle(.entryActionCompleted(record)))))
        await receiveHierarchyInvalidation(store)
        await store.send(folderResponse(
            primaryDestination.id,
            generation: 4,
            .event(.coreBatch(items: [afterPrimary], batchIndex: 0)),
        ))
        await store.receive(\.entryViewLayout.delegate.selectionChanged)
        await store.send(.entryViewLayout(.hierarchy(.folderCollapseRequested(id: additionalDestination.id))))

        XCTAssertNil(store.state.pendingIdentityTransition)
        XCTAssertNil(store.state.entryViewLayout.hierarchy.deferredFolderReplacement(folderID: source.id))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [afterPrimary.id, beforeAdditional.id])
        XCTAssertEqual(
            store.state.entryViewLayout.hierarchy.nodesByID[source.id]?.folder.children,
            [beforePrimary, beforeAdditional],
        )
        await store.skipInFlightEffects()
    }

    /// EVM-002-command_external_refresh_correlation: shared primary collapse는 nil-owner pair까지 함께 종결한다.
    /// - 검증 내용: entryActionCompleted 직후 primary destination C를 collapse해 transition/source hold를 검사한다.
    /// - 사전 조건: primary와 additional이 C generation 4를 공유하고 source D hold가 pre-arm돼 있다.
    /// - 기대 결과: primary와 nil-owner pair가 모두 cancellation terminal로 정산되고 retained source가 유지된다.
    func testSharedPrimaryDestinationCollapseSettlesNilOwnerPair() async {
        let fixture = makeSharedPrimaryTerminalFixture()
        await startSharedPrimaryTerminalFixture(fixture)

        await fixture.store.send(.entryViewLayout(.hierarchy(.folderCollapseRequested(id: fixture.destination.id))))

        XCTAssertNil(fixture.store.state.pendingIdentityTransition)
        XCTAssertNil(fixture.store.state.entryViewLayout.hierarchy.deferredFolderReplacement(
            folderID: fixture.source.id,
        ))
        XCTAssertEqual(
            fixture.store.state.entryViewLayout.hierarchy.nodesByID[fixture.source.id]?.folder.children,
            [fixture.beforePrimary, fixture.beforeAdditional],
        )
        XCTAssertEqual(
            fixture.store.state.entryViewLayout.selectedIds,
            [fixture.beforePrimary.id, fixture.beforeAdditional.id],
        )
        await fixture.store.skipInFlightEffects()
    }

    /// EVM-002-command_external_refresh_correlation: stale destination owner도 collapse cancellation으로 종결한다.
    /// - 검증 내용: generation 3 owner가 남은 transition에서 generation 5 C node를 collapse한다.
    /// - 사전 조건: primary는 이미 migrated이고 explicit additional C pair와 source hold만 pending이다.
    /// - 기대 결과: response generation과 무관하게 exact lexical C pair와 hold가 닫힌다.
    func testStaleAdditionalDestinationCollapseSettlesCanceledOwner() async {
        let source = EntryModel.temporaryFolder(id: "/root/D", name: "D")
        let destination = EntryModel.temporaryFolder(id: "/root/C", name: "C")
        let before = EntryModel.temporaryFolder(id: "/root/D/q", name: "q")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath("/root")
        state.entryViewLayout.entries = [source, destination]
        state.entryViewLayout.hierarchy = .init(rootPath: "/root")
        state.entryViewLayout.hierarchy.nodesByID[source.id] = .init(
            children: [before], loadPhase: .loadingCore, generation: 5,
        )
        state.entryViewLayout.hierarchy.nodesByID[destination.id] = .init(
            children: [], loadPhase: .loadingCore, generation: 5,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([source.id, destination.id])
        state.entryViewLayout.selectedIds = [before.id]
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: "/root/primary",
            afterPath: "/root/primary-after",
            rootPath: "/root",
            refreshGeneration: 1,
            projectionOwner: .root(generation: 1),
            additionalMoves: [
                .init(
                    beforePath: before.id,
                    afterPath: "/root/C/q",
                    sourceOwner: .folder(id: source.id, generation: 3),
                    destinationOwner: .folder(id: destination.id, generation: 3),
                ),
            ],
        )
        state.pendingIdentityTransition?.primaryMigrated = true
        state.entryViewLayout.hierarchy.beginDeferredFolderReplacement(
            folderID: source.id,
            untilEntryID: "/root/C/q",
            holdsUntilMigration: true,
        )
        let store = makeIdentityTransitionStore(state)

        await store.send(.entryViewLayout(.hierarchy(.folderCollapseRequested(id: destination.id))))

        XCTAssertNil(store.state.pendingIdentityTransition)
        XCTAssertNil(store.state.entryViewLayout.hierarchy.deferredFolderReplacement(folderID: source.id))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [before.id])
    }

    /// EVM-002-command_external_refresh_correlation: canonical alias success terminal은 exact primary owner만 종결한다.
    /// - 검증 내용: canonical-equal B coreFinished 뒤 A nil-owner pair와 replacements를 유지하고 A terminal에서 닫는다.
    /// - 사전 조건: distinct lexical alias A/B node가 같은 target과 generation 3을 공유한다.
    /// - 기대 결과: B 뒤 pair 미이전, A 뒤 deterministic settlement와 source selection 보존.
    func testCanonicalAliasSharedPrimaryDestinationTerminalRequiresExactLexicalOwner() async throws {
        let fixture = try makeCanonicalAliasTerminalFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        await startCanonicalAliasTerminalFixture(fixture)

        await fixture.store.send(folderResponse(
            fixture.aliasB.id,
            generation: 3,
            .event(.coreFinished(batchCount: 0)),
        ))
        assertCanonicalAliasTerminalRemainsPending(fixture)

        await fixture.store.send(folderResponse(
            fixture.aliasA.id,
            generation: 3,
            .event(.coreFinished(batchCount: 1)),
        ))
        assertCanonicalAliasTerminalSettled(fixture, destinationChildren: [])
    }

    /// EVM-002-command_external_refresh_correlation: canonical alias failure terminal도 exact primary owner만 종결한다.
    /// - 검증 내용: canonical-equal B failure를 무시하고 A failure에서 nil-owner pair와 replacements를 정리한다.
    /// - 사전 조건: A destination deferred staging과 D source hold가 모두 활성 상태다.
    /// - 기대 결과: B 뒤 상태 무변경, A 뒤 retained snapshots와 selection을 보존한 단일 settlement.
    func testCanonicalAliasSharedPrimaryDestinationFailureRequiresExactLexicalOwner() async throws {
        let fixture = try makeCanonicalAliasTerminalFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        await startCanonicalAliasTerminalFixture(fixture)

        await fixture.store.send(folderResponse(
            fixture.aliasB.id,
            generation: 3,
            .failed(.permissionDenied),
        ))
        assertCanonicalAliasTerminalRemainsPending(fixture)

        await fixture.store.send(folderResponse(
            fixture.aliasA.id,
            generation: 3,
            .failed(.permissionDenied),
        ))
        assertCanonicalAliasTerminalSettled(fixture, destinationChildren: [fixture.oldA])
    }

    /// EVM-002-command_external_refresh_correlation: canonical alias collapse도 exact destination만 취소한다.
    /// - 검증 내용: B collapse 뒤 A transition/holds를 유지하고 A collapse에서만 정산한다.
    /// - 사전 조건: canonical-equal lexical aliases A/B와 A nil-owner shared pair가 있다.
    /// - 기대 결과: B는 no-op, A는 transition과 source/destination replacement를 닫는다.
    func testCanonicalAliasDestinationCollapseRequiresExactLexicalOwner() async throws {
        let fixture = try makeCanonicalAliasTerminalFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        await startCanonicalAliasTerminalFixture(fixture)

        await fixture.store.send(.entryViewLayout(.hierarchy(.folderCollapseRequested(id: fixture.aliasB.id))))
        assertCanonicalAliasTerminalRemainsPending(fixture)

        await fixture.store.send(.entryViewLayout(.hierarchy(.folderCollapseRequested(id: fixture.aliasA.id))))
        assertCanonicalAliasTerminalSettled(fixture, destinationChildren: [])
    }

    private func makeSharedPrimaryTerminalFixture() -> SharedPrimaryTerminalFixture {
        let source = EntryModel.temporaryFolder(id: "/root/D", name: "D")
        let destination = EntryModel.temporaryFolder(id: "/root/C", name: "C")
        let beforePrimary = EntryModel.temporaryFolder(id: "/root/D/p", name: "p")
        let beforeAdditional = EntryModel.temporaryFolder(id: "/root/D/q", name: "q")
        let oldDestinationChild = EntryModel.temporaryFolder(id: "/root/C/old", name: "old")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath("/root")
        state.entryViewLayout.entries = [source, destination]
        state.entryViewLayout.hierarchy = .init(rootPath: "/root")
        state.entryViewLayout.hierarchy.nodesByID[source.id] = .init(
            children: [beforePrimary, beforeAdditional], loadPhase: .loaded, generation: 3, coreFinished: true,
        )
        state.entryViewLayout.hierarchy.nodesByID[destination.id] = .init(
            children: [oldDestinationChild], loadPhase: .loaded, generation: 3, coreFinished: true,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([source.id, destination.id])
        state.entryViewLayout.selectedIds = [beforePrimary.id, beforeAdditional.id]
        let record = EntryActionRecord(
            operationKind: .pasteFileMove,
            targets: [
                .init(beforePath: beforePrimary.id, afterPath: "/root/C/p"),
                .init(beforePath: beforeAdditional.id, afterPath: "/root/C/q"),
            ],
        )
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.entryQuickLookClient = .previewValue
            $0.entryLoadingClient.stagedLoadItems = { _, _, _ in AsyncThrowingStream { _ in } }
        }
        store.exhaustivity = .off
        return .init(
            store: store,
            record: record,
            source: source,
            destination: destination,
            beforePrimary: beforePrimary,
            beforeAdditional: beforeAdditional,
            oldDestinationChild: oldDestinationChild,
        )
    }

    private func startSharedPrimaryTerminalFixture(_ fixture: SharedPrimaryTerminalFixture) async {
        await fixture.store.send(.entryViewLayout(.entryOperations(.lifecycle(.entryActionCompleted(fixture.record)))))
        await fixture.store.receive { action in
            guard case .entryViewLayout(.hierarchy(.hierarchyInvalidated)) = action else { return false }
            return true
        }
        XCTAssertNil(fixture.store.state.pendingIdentityTransition?.additionalMoves.first?.destinationOwner)
        XCTAssertNotNil(fixture.store.state.entryViewLayout.hierarchy.deferredFolderReplacement(
            folderID: fixture.source.id,
        ))
    }

    private func makeIdentityTransitionStore(
        _ state: FileManagerContentState,
    ) -> TestStore<FileManagerContentState, FileManagerContentAction> {
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.entryQuickLookClient = .previewValue
            $0.entryLoadingClient.stagedLoadItems = { _, _, _ in AsyncThrowingStream { _ in } }
        }
        store.exhaustivity = .off
        return store
    }

    private func receiveHierarchyInvalidation(
        _ store: TestStore<FileManagerContentState, FileManagerContentAction>,
    ) async {
        await store.receive { action in
            guard case .entryViewLayout(.hierarchy(.hierarchyInvalidated)) = action else { return false }
            return true
        }
    }

    private func makeCanonicalAliasTerminalFixture() throws -> CanonicalAliasTerminalFixture {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let targetURL = rootURL.appendingPathComponent("target", isDirectory: true)
        let aliasAURL = rootURL.appendingPathComponent("alias-a")
        let aliasBURL = rootURL.appendingPathComponent("alias-b")
        try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: aliasAURL, withDestinationURL: targetURL)
        try FileManager.default.createSymbolicLink(at: aliasBURL, withDestinationURL: targetURL)
        let source = EntryModel.temporaryFolder(id: rootURL.appendingPathComponent("D").path, name: "D")
        let aliasA = EntryModel.temporaryFolder(id: aliasAURL.path, name: "alias-a")
        let aliasB = EntryModel.temporaryFolder(id: aliasBURL.path, name: "alias-b")
        let beforePrimary = EntryModel.temporaryFolder(id: source.id + "/p", name: "p")
        let beforeAdditional = EntryModel.temporaryFolder(id: source.id + "/q", name: "q")
        let oldA = EntryModel.temporaryFolder(id: aliasA.id + "/old", name: "old-a")
        let oldB = EntryModel.temporaryFolder(id: aliasB.id + "/old", name: "old-b")
        let afterPrimary = aliasA.id + "/p"
        let afterAdditional = aliasA.id + "/q"
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootURL.path)
        state.entryViewLayout.entries = [source, aliasA, aliasB]
        state.entryViewLayout.hierarchy = .init(rootPath: rootURL.path)
        state.entryViewLayout.hierarchy.nodesByID[source.id] = .init(
            folder: .init(
                children: [beforePrimary, beforeAdditional],
                retainsPreviousGenerationChildren: true,
            ),
            generation: 3,
            loadPhase: .loadingCore,
        )
        state.entryViewLayout.hierarchy.nodesByID[aliasA.id] = .init(
            children: [oldA], loadPhase: .loadingCore, generation: 3,
        )
        state.entryViewLayout.hierarchy.nodesByID[aliasB.id] = .init(
            children: [oldB], loadPhase: .loadingCore, generation: 3,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([source.id, aliasA.id, aliasB.id])
        state.entryViewLayout.selectedIds = [beforePrimary.id, beforeAdditional.id]
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: beforePrimary.id,
            afterPath: afterPrimary,
            rootPath: rootURL.path,
            refreshGeneration: 1,
            projectionOwner: .folder(id: aliasA.id, generation: 3),
            preservationOwner: .folder(id: source.id, generation: 3),
            additionalMoves: [
                .init(
                    beforePath: beforeAdditional.id,
                    afterPath: afterAdditional,
                    sourceOwner: .folder(id: source.id, generation: 3),
                ),
            ],
        )
        state.entryViewLayout.hierarchy.beginDeferredFolderReplacement(
            folderID: source.id,
            untilEntryID: afterPrimary,
            holdsUntilMigration: true,
        )
        let store = makeFileManagerContentFeatureStore(initialState: state)
        store.exhaustivity = .off
        return .init(
            store: store,
            rootURL: rootURL,
            source: source,
            aliasA: aliasA,
            aliasB: aliasB,
            beforePrimary: beforePrimary,
            beforeAdditional: beforeAdditional,
            oldA: oldA,
        )
    }

    private func startCanonicalAliasTerminalFixture(_ fixture: CanonicalAliasTerminalFixture) async {
        XCTAssertEqual(
            FileManagerContentIdentityTransitionCoordinator.canonicalizedPath(fixture.aliasA.id),
            FileManagerContentIdentityTransitionCoordinator.canonicalizedPath(fixture.aliasB.id),
        )
        await fixture.store.send(folderResponse(
            fixture.aliasA.id,
            generation: 3,
            .event(.coreBatch(items: [], batchIndex: 0)),
        ))
        XCTAssertNotNil(fixture.store.state.entryViewLayout.hierarchy.deferredFolderReplacement(
            folderID: fixture.aliasA.id,
        ))
    }

    private func assertCanonicalAliasTerminalRemainsPending(_ fixture: CanonicalAliasTerminalFixture) {
        XCTAssertEqual(fixture.store.state.pendingIdentityTransition?.additionalMoves.first?.migrated, false)
        XCTAssertNotNil(fixture.store.state.entryViewLayout.hierarchy.deferredFolderReplacement(
            folderID: fixture.aliasA.id,
        ))
        XCTAssertNotNil(fixture.store.state.entryViewLayout.hierarchy.deferredFolderReplacement(
            folderID: fixture.source.id,
        ))
        XCTAssertEqual(
            fixture.store.state.entryViewLayout.selectedIds,
            [fixture.beforePrimary.id, fixture.beforeAdditional.id],
        )
    }

    private func assertCanonicalAliasTerminalSettled(
        _ fixture: CanonicalAliasTerminalFixture,
        destinationChildren: [EntryModel],
    ) {
        XCTAssertNil(fixture.store.state.pendingIdentityTransition)
        XCTAssertNil(fixture.store.state.entryViewLayout.hierarchy.deferredFolderReplacement(
            folderID: fixture.aliasA.id,
        ))
        let sourceReplacement = fixture.store.state.entryViewLayout.hierarchy.deferredFolderReplacement(
            folderID: fixture.source.id,
        )
        XCTAssertEqual(sourceReplacement?.holdsUntilMigration, true)
        XCTAssertEqual(sourceReplacement?.migrationCompleted, true)
        XCTAssertEqual(
            fixture.store.state.entryViewLayout.hierarchy.nodesByID[fixture.source.id]?.folder.children,
            [fixture.beforePrimary, fixture.beforeAdditional],
        )
        XCTAssertEqual(
            fixture.store.state.entryViewLayout.hierarchy.nodesByID[fixture.aliasA.id]?.folder.children,
            destinationChildren,
        )
        XCTAssertEqual(
            fixture.store.state.entryViewLayout.selectedIds,
            [fixture.beforePrimary.id, fixture.beforeAdditional.id],
        )
    }

    private func folderResponse(
        _ folderID: EntryModel.ID,
        generation: Int,
        _ response: EntryListFolderChildrenResponse,
    ) -> FileManagerContentAction {
        .entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: 0,
            folderID: folderID,
            folderGeneration: generation,
            response,
        )))
    }
}

private struct SharedPrimaryTerminalFixture {
    let store: TestStore<FileManagerContentState, FileManagerContentAction>
    let record: EntryActionRecord
    let source: EntryModel
    let destination: EntryModel
    let beforePrimary: EntryModel
    let beforeAdditional: EntryModel
    let oldDestinationChild: EntryModel
}

private struct CanonicalAliasTerminalFixture {
    let store: TestStore<FileManagerContentState, FileManagerContentAction>
    let rootURL: URL
    let source: EntryModel
    let aliasA: EntryModel
    let aliasB: EntryModel
    let beforePrimary: EntryModel
    let beforeAdditional: EntryModel
    let oldA: EntryModel
}
