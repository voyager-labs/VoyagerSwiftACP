@_spi(Internals)
import ComposableArchitecture
import Foundation
@testable import VoyagerEntitiesCollection
import VoyagerShared
import XCTest

@MainActor
final class RCL002OpenSavedCollectionTests: XCTestCase {
    // VOY-570 Linear AC mapping (Collection save owner):
    // AC11 -> testBuiltInCollectionDirectSave_canonicalDestinationsAreReadOnly
    // AC11 -> testBuiltInCollectionSavePanel_canonicalDestinationIsReadOnly
    // AC12 -> testBuiltInCollectionSaveAs_nonCanonicalDestinationSucceeds

    // MARK: - RCL-002-delete_collection

    /// RCL-002-delete_collection: collection 삭제는 file/app command layer 소유
    /// Collection package에는 delete action/client가 없으므로 실제 삭제는 sandbox fixture 기반 app/file-client suite로 분리한다.
    /// - 검증 내용: package contract 부재와 app/file-client ownership 명시
    /// - 사전 조건: `.voycoll` fixture는 `CollectionFixtureSandbox`로 원본 보호 후 사용 가능
    /// - 기대 결과: delete AC는 app/file-client spec-owner suite에서 검증 필요
    func testDeleteCollection_requiresFileClientFocusedSuite() throws {
        throw XCTSkip(
            "Collection package has no delete command; migrate delete AC to app/file-client "
                + "spec-owner suite with sandboxed .voycoll fixture.",
        )
    }

    // MARK: - RCL-002-rename_collection

    /// RCL-002-rename_collection: collection rename은 file/app command layer 소유
    /// Collection package save contract는 파일 쓰기를 검증하지만 rename command는 별도 action/client가 필요하다.
    /// - 검증 내용: rename boundary 명시
    /// - 사전 조건: save existing/save as new package paths는 이 suite에서 검증됨
    /// - 기대 결과: rename AC는 app/file-client spec-owner suite에서 검증 필요
    func testRenameCollection_requiresFileClientFocusedSuite() throws {
        throw XCTSkip(
            "Collection package has no rename command; migrate rename AC to app/file-client spec-owner suite.",
        )
    }

    // MARK: - RCL-002-open_saved_collection

    /// RCL-002-open_saved_collection: 실제 `.voycoll` 패키지 fixture를 열면 collection 정의가 복원된다.
    /// 저장된 Collection 패키지의 `collection.plist`를 제품 live client로 로드하는 real-file 계약을 검증한다.
    /// - 검증 내용: query, scope, schema, package container, compatibility metadata
    /// - 사전 조건: `fixtures/fixtures/collections/basic_collection.voycoll`을 sandbox로 복사해 사용
    /// - 기대 결과: 원본 fixture를 변경하지 않고 package payload가 definition-only collection으로 복원됨
    func testOpenSavedCollection_withBasicPackageFixture_restoresDefinition() async throws {
        let sandbox = try CollectionFixtureSandbox.copyingBasicCollection()
        defer { try? sandbox.cleanup() }
        let result = try await CollectionFileClient.liveValue.load(sandbox.fileURL)

        XCTAssertEqual(result.containerFormat, .package)
        XCTAssertEqual(result.file.id, "rcl-basic-collection")
        XCTAssertEqual(result.file.name, "RCL Basic Collection")
        XCTAssertEqual(result.file.query, "quarterly report")
        XCTAssertEqual(result.file.scopes, ["/VoyagerFixtures/Documents", "/VoyagerFixtures/Notes"])
        XCTAssertEqual(result.file.schemaVersion, SchemaVersion(major: 1, minor: 0))
        XCTAssertNil(result.file.snapshot)
        XCTAssertEqual(result.compatibility.sourceSchemaVersion, SchemaVersion(major: 1, minor: 0))
        XCTAssertFalse(result.compatibility.writeBackAllowed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    /// RCL-002-open_saved_collection: 현재 포맷으로 저장한 collection은 다시 열었을 때 filter 정의를 유지한다.
    /// fixture에서 읽은 Collection을 live save 경로로 다시 저장해 save/open/reopen 계약을 검증한다.
    /// - 검증 내용: `CollectionFileClient.save`가 `.voycoll/collection.plist` binary plist를 만들고 재로드 시 condition을 유지
    /// - 사전 조건: `fixtures/fixtures/collections/condition_collection.voycoll`을 sandbox로 복사해 사용
    /// - 기대 결과: 저장된 package를 다시 열면 query, scope, excluded scope, condition count가 동일함
    func testSaveAndReopenCollection_withConditionFixture_preservesFilterDefinition() async throws {
        let sandbox = try CollectionFixtureSandbox.copyingDirectory(
            from: "fixtures/fixtures/collections/condition_collection.voycoll",
        )
        defer { try? sandbox.cleanup() }

        let opened = try await CollectionFileClient.liveValue.load(sandbox.fileURL)
        let savedURL = sandbox.root.appendingPathComponent("reopened_condition_collection.voycoll")

        try await CollectionFileClient.liveValue.save(opened.file, savedURL)
        let reopened = try await CollectionFileClient.liveValue.load(savedURL)
        let payloadURL = savedURL.appendingPathComponent("collection.plist")
        let payloadData = try Data(contentsOf: payloadURL)

        XCTAssertEqual(reopened.containerFormat, .package)
        XCTAssertEqual(reopened.file.query, opened.file.query)
        XCTAssertEqual(reopened.file.scopes, opened.file.scopes)
        XCTAssertEqual(reopened.file.excludedScopes, opened.file.excludedScopes)
        XCTAssertEqual(reopened.file.conditions.count, 2)
        XCTAssertEqual(reopened.file.conditions.map(\.propertyKey), ["kind", "size"])
        XCTAssertTrue(payloadData.starts(with: Data("bplist".utf8)))
    }

    // MARK: - RCL-002-restore_saved_collection_snapshot

    /// RCL-002-restore_saved_collection_snapshot: snapshot 포함 `.voycoll` fixture를 열면 snapshot-first 표시 재료가 복원된다.
    /// 저장된 snapshot과 snapshotMeta가 hydration 경로에서 synthetic response로 변환되는지 검증한다.
    /// - 검증 내용: snapshot item, snapshot metadata, applied filter, synthetic response
    /// - 사전 조건: `fixtures/fixtures/collections/snapshot_collection.voycoll`을 sandbox로 복사해 사용
    /// - 기대 결과: 파일 로드 직후 refresh 전에도 snapshot item 2개를 표시할 수 있음
    func testRestoreSavedCollectionSnapshot_withSnapshotFixture_buildsSyntheticResponse() async throws {
        let sandbox = try CollectionFixtureSandbox.copyingDirectory(
            from: "fixtures/fixtures/collections/snapshot_collection.voycoll",
        )
        defer { try? sandbox.cleanup() }

        let result = try await CollectionFileClient.liveValue.load(sandbox.fileURL)
        let response = CollectionSnapshotHydration.syntheticSearchResponse(for: result.file)

        XCTAssertEqual(result.containerFormat, .package)
        XCTAssertEqual(result.file.schemaVersion, SchemaVersion(major: 1, minor: 1))
        XCTAssertEqual(result.file.snapshot?.items.count, 2)
        XCTAssertEqual(result.file.snapshotMeta?.itemCount, 2)
        XCTAssertTrue(result.compatibility.writeBackAllowed)
        XCTAssertEqual(response?.itemCount, 2)
        XCTAssertEqual(response?.items, [
            VoyagerShared.JSONValue.string("/VoyagerFixtures/Projects/RCL/spec.md"),
            VoyagerShared.JSONValue.string("/VoyagerFixtures/Projects/RCL/notes.txt"),
        ])
        XCTAssertEqual(result.file.query, "design review")
        XCTAssertTrue(result.file.includeDirectories)
        XCTAssertEqual(response?.appliedFilters?.scopes, ["/VoyagerFixtures/Projects"])
    }

    /// RCL-002-restore_saved_collection_snapshot: stale snapshot fixture도 refresh 전 snapshot-first 표시가 가능해야 한다.
    /// 오래된 capturedAt은 자동화에서 stale refresh 트리거와 분리하고, 여기서는 저장 snapshot 복원 계약만 검증한다.
    /// - 검증 내용: stale fixture의 snapshot payload와 synthetic response 생성 가능 여부
    /// - 사전 조건: `fixtures/fixtures/collections/stale_snapshot_collection.voycoll`을 sandbox로 복사해 사용
    /// - 기대 결과: stale 판정과 별개로 저장된 snapshot item은 먼저 복원 가능함
    func testRestoreSavedCollectionSnapshot_withStaleSnapshotFixture_stillBuildsSyntheticResponse() async throws {
        let sandbox = try CollectionFixtureSandbox.copyingDirectory(
            from: "fixtures/fixtures/collections/stale_snapshot_collection.voycoll",
        )
        defer { try? sandbox.cleanup() }

        let result = try await CollectionFileClient.liveValue.load(sandbox.fileURL)
        let response = CollectionSnapshotHydration.syntheticSearchResponse(for: result.file)

        XCTAssertEqual(result.file.schemaVersion, SchemaVersion(major: 1, minor: 1))
        XCTAssertEqual(result.file.snapshot?.items.count, 2)
        XCTAssertEqual(result.file.snapshotMeta?.relevanceRoots, ["/VoyagerFixtures/Migrations"])
        XCTAssertEqual(response?.itemCount, 2)
        XCTAssertEqual(result.file.query, "migration plan")
        XCTAssertEqual(response?.appliedFilters?.scopes, ["/VoyagerFixtures/Migrations"])
    }

    // MARK: - RCL-002-save_current_filter_as_new_collection

    /// RCL-002-save_current_filter_as_new_collection: 새 collection 저장은 선택 URL에 `.voycoll` 패키지를 저장한다.
    /// save panel에서 선택된 경로가 실제 저장 요청과 completion으로 이어지는 reducer 계약을 검증한다.
    /// - 검증 내용: pending save, selected URL extension 보정, saved file context
    /// - 사전 조건: query, scope, snapshot item을 가진 새 collection save payload
    /// - 기대 결과: 선택 경로는 `.voycoll`로 저장되고 completion은 동일한 context를 반환함
    func testSaveCurrentFilterAsNewCollection_withSelectedURL_savesVoycollPackage() async throws {
        let sandbox = try CollectionFixtureSandbox.copyingBasicCollection()
        defer { try? sandbox.cleanup() }
        let payload = makeSavePayload(
            query: "new report",
            snapshotItems: [.string("/VoyagerFixtures/Documents/report.md")],
        )
        let selectedURL = sandbox.root.appendingPathComponent("RCL Saved Collection")
        let recorder = CollectionFileSaveRecorder()
        let store = TestStore(initialState: CollectionState()) {
            CollectionFeature()
        } withDependencies: {
            $0.collectionSavePanelClient.defaultSaveDirectory = { _ in sandbox.root }
            $0.collectionSavePanelClient.presentSavePanel = { _ in selectedURL }
            $0.collectionFileClient.save = recorder.save
        }

        await store.send(.saveRequested(payload)) {
            $0.isSaving = true
            $0.pendingSaveContext = payload.context
            $0.pendingSave = makeSaveSnapshot(
                query: "new report",
                snapshotItems: [.string("/VoyagerFixtures/Documents/report.md")],
            )
        }
        await store.receive(\.savePanelResponse)
        await store.receive(\.saveCompleted) {
            $0.isSaving = false
            $0.pendingSave = nil
            $0.pendingSaveContext = nil
        }

        let saved = try XCTUnwrap(recorder.lastSave)
        XCTAssertEqual(saved.url.path, sandbox.root.appendingPathComponent("RCL Saved Collection.voycoll").path)
        XCTAssertEqual(saved.file.query, "new report")
        XCTAssertEqual(saved.file.snapshot?.items, [.string("/VoyagerFixtures/Documents/report.md")])
    }

    // MARK: - RCL-002-ensure_built_in_collections

    /// RCL-002-ensure_built_in_collections: canonical built-in Collection에는 direct Save를 허용하지 않는다.
    /// 최종 저장 목적지를 identity classifier로 검사해 app-managed package 덮어쓰기를 차단하는 경로를 검증한다.
    /// - 검증 내용: Recents/All Tags feedback 전문과 file save 미호출
    /// - 사전 조건: injected Application Support 아래 두 canonical `.voycoll` URL
    /// - 기대 결과: 두 저장 모두 read-only feedback을 내고 저장 호출은 0회임
    func testBuiltInCollectionDirectSave_canonicalDestinationsAreReadOnly() async {
        let applicationSupportURL = URL(fileURLWithPath: "/tmp/Application Support", isDirectory: true)
        let payload = makeSavePayload(query: "protected report", snapshotItems: nil)

        for identity in BuiltInCollectionIdentity.allCases {
            let recorder = CollectionFileSaveRecorder()
            let destinationURL = identity.canonicalPackageURL(
                applicationSupportURL: applicationSupportURL,
            )
            let store = TestStore(initialState: CollectionState()) {
                CollectionFeature()
            } withDependencies: {
                $0.fileManagerClient.urlsForDirectory = { _, _ in [applicationSupportURL] }
                $0.collectionFileClient.save = recorder.save
            }

            await store.send(.saveToExisting(payload, destinationURL))
            await store.receive(\.delegate.saveFeedback, builtInReadOnlyFeedback)

            XCTAssertEqual(recorder.invocationCount, 0)
            XCTAssertNil(recorder.lastSave)
            XCTAssertFalse(store.state.isSaving)
            XCTAssertNil(store.state.pendingSave)
            XCTAssertNil(store.state.pendingSaveContext)
        }
    }

    /// RCL-002-ensure_built_in_collections: Save As panel에서 canonical built-in URL을 선택해도 저장하지 않는다.
    /// panel 응답이 direct Save와 동일한 최종 목적지 guard를 통과하는 경로를 검증한다.
    /// - 검증 내용: panel pending state 정리, 정확한 read-only feedback, file save 미호출
    /// - 사전 조건: save panel이 canonical All Tags package URL을 반환함
    /// - 기대 결과: pendingSave/isSaving이 해제되고 저장 호출은 0회임
    func testBuiltInCollectionSavePanel_canonicalDestinationIsReadOnly() async {
        let applicationSupportURL = URL(fileURLWithPath: "/tmp/Application Support", isDirectory: true)
        let destinationURL = BuiltInCollectionIdentity.allTags.canonicalPackageURL(
            applicationSupportURL: applicationSupportURL,
        )
        let payload = makeSavePayload(query: "protected tags", snapshotItems: nil)
        let recorder = CollectionFileSaveRecorder()
        let store = TestStore(initialState: CollectionState()) {
            CollectionFeature()
        } withDependencies: {
            $0.fileManagerClient.urlsForDirectory = { _, _ in [applicationSupportURL] }
            $0.collectionSavePanelClient.defaultSaveDirectory = { _ in applicationSupportURL }
            $0.collectionSavePanelClient.presentSavePanel = { _ in destinationURL }
            $0.collectionFileClient.save = recorder.save
        }

        await store.send(.saveRequested(payload)) {
            $0.isSaving = true
            $0.pendingSaveContext = payload.context
            $0.pendingSave = makeSaveSnapshot(query: "protected tags", snapshotItems: nil)
        }
        await store.receive(\.savePanelResponse) {
            $0.isSaving = false
            $0.pendingSave = nil
            $0.pendingSaveContext = nil
        }
        await store.receive(\.delegate.saveFeedback, builtInReadOnlyFeedback)

        XCTAssertEqual(recorder.invocationCount, 0)
        XCTAssertNil(recorder.lastSave)
    }

    /// RCL-002-ensure_built_in_collections: canonical filename의 대소문자 variant도 Save As로 덮어쓸 수 없다.
    /// - 기대 결과: 확장자 보정 여부와 무관하게 두 destination 모두 저장되지 않음
    func testBuiltInCollectionSavePanel_caseVariantCanonicalDestinationsAreReadOnly() async {
        let applicationSupportURL = URL(fileURLWithPath: "/tmp/Application Support", isDirectory: true)
        let canonicalRootURL = BuiltInCollectionIdentity.canonicalRootURL(
            applicationSupportURL: applicationSupportURL,
        )
        await assertCaseVariantDestinationsAreReadOnly(
            [
                canonicalRootURL.appendingPathComponent("ALL-TAGS"),
                canonicalRootURL.appendingPathComponent("ReCeNtS.VoYcOlL"),
            ],
            applicationSupportURL: applicationSupportURL,
        )
    }

    /// RCL-002-ensure_built_in_collections: built-in root의 sibling user destination에는 Save As가 가능하다.
    /// exact canonical package만 차단하고 일반 사용자 Collection 저장 계약을 보존하는 경로를 검증한다.
    /// - 검증 내용: sibling URL 확장자 보정, 한 번의 file save, read-only feedback 부재
    /// - 사전 조건: Application Support `Voyager/Collections` 아래 noncanonical user URL 선택
    /// - 기대 결과: 선택 URL에 `.voycoll`을 붙여 정상 저장함
    func testBuiltInCollectionSaveAs_nonCanonicalDestinationSucceeds() async throws {
        let applicationSupportURL = URL(fileURLWithPath: "/tmp/Application Support", isDirectory: true)
        let selectedURL = applicationSupportURL
            .appendingPathComponent("Voyager/Collections", isDirectory: true)
            .appendingPathComponent("User Collection")
        let payload = makeSavePayload(query: "editable copy", snapshotItems: nil)
        let recorder = CollectionFileSaveRecorder()
        let store = TestStore(initialState: CollectionState()) {
            CollectionFeature()
        } withDependencies: {
            $0.fileManagerClient.urlsForDirectory = { _, _ in [applicationSupportURL] }
            $0.collectionSavePanelClient.defaultSaveDirectory = { _ in applicationSupportURL }
            $0.collectionSavePanelClient.presentSavePanel = { _ in selectedURL }
            $0.collectionFileClient.save = recorder.save
        }

        await store.send(.saveRequested(payload)) {
            $0.isSaving = true
            $0.pendingSaveContext = payload.context
            $0.pendingSave = makeSaveSnapshot(query: "editable copy", snapshotItems: nil)
        }
        await store.receive(\.savePanelResponse)
        await store.receive(\.saveCompleted) {
            $0.isSaving = false
            $0.pendingSave = nil
            $0.pendingSaveContext = nil
        }

        XCTAssertEqual(recorder.invocationCount, 1)
        let saved = try XCTUnwrap(recorder.lastSave)
        XCTAssertEqual(
            saved.url.path,
            "/tmp/Application Support/Voyager/Collections/User Collection.voycoll",
        )
        XCTAssertEqual(saved.file.query, "editable copy")
    }

    /// RCL-002-ensure_built_in_collections: 기존 package symlink와 alias를 통한 canonical Save를 차단한다.
    /// 최종 목적지가 Recents package로 resolve되는 두 filesystem 우회 경로를 검증한다.
    /// - 검증 내용: symlink/alias resolve 후 read-only feedback과 file save 미호출
    /// - 사전 조건: 실제 canonical Recents package를 가리키는 `.voycoll` symlink와 bookmark alias
    /// - 기대 결과: canonical로 resolve되는 두 경로만 차단하고 link target인 일반 package 직접 저장은 허용
    func testBuiltInCollectionDirectSave_filesystemLinksBlockOnlyManagedDestination() async throws {
        let fixture = try CollectionSaveProtectionFixture()
        defer { fixture.cleanup() }

        try await fixture.assertCanonicalLinksAreBlocked()
        try await fixture.assertCanonicalLinkTargetRemainsEditable()
    }

    /// RCL-002-ensure_built_in_collections: symlink parent 아래 아직 없는 canonical child Save As를 차단한다.
    /// package가 생성되기 전에도 가장 가까운 기존 parent를 resolve해 최종 목적지를 판정한다.
    /// - 검증 내용: 확장자 보정 전 선택 URL의 parent symlink 해석과 file save 미호출
    /// - 사전 조건: canonical BuiltIn root를 가리키는 symlink와 존재하지 않는 `all-tags.voycoll` child
    /// - 기대 결과: 최종 child가 canonical All Tags로 분류되어 저장되지 않음
    func testBuiltInCollectionSaveAs_missingChildUnderSymlinkedParentIsReadOnly() async throws {
        let sandboxURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RCL002SaveProtection-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: sandboxURL) }
        let applicationSupportURL = sandboxURL.appendingPathComponent("Application Support", isDirectory: true)
        let canonicalRootURL = BuiltInCollectionIdentity.canonicalRootURL(
            applicationSupportURL: applicationSupportURL,
        )
        try FileManager.default.createDirectory(at: canonicalRootURL, withIntermediateDirectories: true)
        let symlinkedRootURL = sandboxURL.appendingPathComponent("BuiltIn Link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: symlinkedRootURL, withDestinationURL: canonicalRootURL)
        let selectedURL = symlinkedRootURL.appendingPathComponent("all-tags")
        var fileManagerClient = FileManagerClient.liveValue
        fileManagerClient.urlsForDirectory = { _, _ in [applicationSupportURL] }
        let payload = makeSavePayload(query: "protected missing child", snapshotItems: nil)
        let recorder = CollectionFileSaveRecorder()
        let store = TestStore(initialState: CollectionState()) {
            CollectionFeature()
        } withDependencies: {
            $0.fileManagerClient = fileManagerClient
            $0.collectionSavePanelClient.defaultSaveDirectory = { _ in sandboxURL }
            $0.collectionSavePanelClient.presentSavePanel = { _ in selectedURL }
            $0.collectionFileClient.save = recorder.save
        }

        await store.send(.saveRequested(payload)) {
            $0.isSaving = true
            $0.pendingSaveContext = payload.context
            $0.pendingSave = makeSaveSnapshot(query: "protected missing child", snapshotItems: nil)
        }
        await store.receive(\.savePanelResponse) {
            $0.isSaving = false
            $0.pendingSave = nil
            $0.pendingSaveContext = nil
        }
        await store.receive(\.delegate.saveFeedback, builtInReadOnlyFeedback)

        XCTAssertEqual(recorder.invocationCount, 0)
    }

    /// RCL-002-ensure_built_in_collections: writeback 중 canonical destination 차단은 transient state를 남기지 않는다.
    /// refresh writeback 저장이 거부될 때 기존 failure cleanup과 동일하게 session inflight를 종료하는 경로를 검증한다.
    /// - 검증 내용: isSaving/pendingSave 해제, writeback phase 종료, file save 미호출
    /// - 사전 조건: hydrated snapshot session이 canonical Recents URL로 writeback 중임
    /// - 기대 결과: session은 refreshFailed 안정 상태가 되고 저장 호출은 0회임
    func testBuiltInCollectionBlockedSave_releasesWriteBackState() async {
        let applicationSupportURL = URL(fileURLWithPath: "/tmp/Application Support", isDirectory: true)
        let destinationURL = BuiltInCollectionIdentity.recents.canonicalPackageURL(
            applicationSupportURL: applicationSupportURL,
        )
        let payload = makeSavePayload(query: "writeback", snapshotItems: nil)
        var state = CollectionState()
        state.collectionSession.phase = .opened(
            kind: .hydratedSnapshot,
            base: .stale,
            inflight: .writingBackRefreshedSnapshot,
        )
        let recorder = CollectionFileSaveRecorder()
        let store = TestStore(initialState: state) {
            CollectionFeature()
        } withDependencies: {
            $0.fileManagerClient.urlsForDirectory = { _, _ in [applicationSupportURL] }
            $0.collectionFileClient.save = recorder.save
        }

        await store.send(.saveToExisting(payload, destinationURL)) {
            $0.collectionSession.phase = .refreshFailed(kind: .hydratedSnapshot)
        }
        await store.receive(\.delegate.saveFeedback, builtInReadOnlyFeedback)

        XCTAssertEqual(recorder.invocationCount, 0)
        XCTAssertNil(recorder.lastSave)
        XCTAssertFalse(store.state.isSaving)
        XCTAssertNil(store.state.pendingSave)
        XCTAssertNil(store.state.pendingSaveContext)
        XCTAssertFalse(store.state.collectionSession.phase.isInflightWriteBack)
        XCTAssertFalse(store.state.collectionSession.phase.isInflightRefresh)
    }

    // MARK: - RCL-002-save_collection_filter_changes

    /// RCL-002-save_collection_filter_changes: 기존 collection 저장은 열린 파일 경로에 현재 filter 정의를 덮어쓴다.
    /// 기존 파일 저장 액션이 save panel 없이 file client 저장과 completion으로 이어지는지 검증한다.
    /// - 검증 내용: saveToExisting URL, saved context, pending state reset
    /// - 사전 조건: dirty context를 가진 opened collection payload와 기존 `.voycoll` URL
    /// - 기대 결과: 기존 URL에 저장되고 completion 후 저장 진행 상태가 해제됨
    func testSaveCollectionFilterChanges_withExistingURL_writesCurrentDefinition() async throws {
        let sandbox = try CollectionFixtureSandbox.copyingBasicCollection()
        defer { try? sandbox.cleanup() }
        let payload = makeSavePayload(query: "updated report", snapshotItems: nil)
        let existingURL = sandbox.root.appendingPathComponent("existing_collection.voycoll")
        let recorder = CollectionFileSaveRecorder()
        let store = TestStore(initialState: CollectionState()) {
            CollectionFeature()
        } withDependencies: {
            $0.collectionFileClient.save = recorder.save
        }

        await store.send(.saveToExisting(payload, existingURL)) {
            $0.isSaving = true
        }
        await store.receive(\.saveCompleted) {
            $0.isSaving = false
            $0.pendingSave = nil
            $0.pendingSaveContext = nil
        }

        let saved = try XCTUnwrap(recorder.lastSave)
        XCTAssertEqual(saved.url, existingURL)
        XCTAssertEqual(saved.file.query, "updated report")
        XCTAssertEqual(saved.file.scopes, ["/VoyagerFixtures/Documents"])
    }

    // MARK: - RCL-002-discard_collection_filter_changes

    /// RCL-002-discard_collection_filter_changes: discard는 baseline filter 정의로 draft를 되돌린다.
    /// 저장되지 않은 collection context 변경이 baseline으로 복원되고 delegate payload가 전달되는지 검증한다.
    /// - 검증 내용: collectionContext 복원, draftRestorePrepared delegate
    /// - 사전 조건: baseline과 현재 context가 다른 열린 collection session
    /// - 기대 결과: 현재 context가 baseline으로 되돌아가고 opened URL이 delegate에 포함됨
    func testDiscardCollectionFilterChanges_withDirtyContext_restoresBaseline() async throws {
        let baseline = CollectionContext(query: "baseline", scopes: ["/VoyagerFixtures/Documents"], conditions: [])
        var state = CollectionState()
        state.collectionContext = CollectionContext(
            query: "changed",
            scopes: ["/VoyagerFixtures/Notes"],
            conditions: [],
        )
        state.collectionSession.metadata.baseline = CollectionBaseline(context: baseline)
        state.collectionSession.document = .init(
            url: URL(fileURLWithPath: "/tmp/baseline.voycoll"),
            name: "baseline",
            compatibility: nil,
        )

        let actions = await reduce(&state, action: .draftDiscardRequested)

        XCTAssertEqual(state.collectionContext, baseline)
        let payload = try XCTUnwrap(draftRestore(from: actions))
        XCTAssertEqual(payload.context, baseline)
        XCTAssertEqual(payload.openedURL?.path, "/tmp/baseline.voycoll")
    }

    // MARK: - RCL-002-indicate_unsaved_collection_filter_changes

    /// RCL-002-indicate_unsaved_collection_filter_changes: baseline과 다른 filter 정의는 unsaved 상태로 판단된다.
    /// reducer state의 dirty/canSave 계약을 통해 저장되지 않은 변경 indicator의 입력 상태를 검증한다.
    /// - 검증 내용: isDirty와 canSave 계산 결과
    /// - 사전 조건: 열린 collection baseline과 현재 query가 다른 collection state
    /// - 기대 결과: dirty 상태이며 collection mode에서 save 가능 상태가 됨
    func testIndicateUnsavedCollectionFilterChanges_withDirtyContext_enablesSaveIndicator() {
        let baseline = CollectionContext(query: "baseline", scopes: ["/VoyagerFixtures/Documents"], conditions: [])
        var state = CollectionState()
        state.collectionSession.metadata.baseline = CollectionBaseline(context: baseline)
        state.collectionContext = CollectionContext(
            query: "changed",
            scopes: ["/VoyagerFixtures/Documents"],
            conditions: [],
        )

        XCTAssertTrue(state.isDirty)
        XCTAssertTrue(state.canSave(isCollectionMode: true))
        XCTAssertFalse(state.canSave(isCollectionMode: false))
    }

    /// RCL-002-indicate_unsaved_collection_filter_changes: 비의미적 filter 표현 차이는 unsaved로 표시하지 않음
    /// query 공백, scope 순서/표준화, condition label/value 공백 차이를 semantic dirty 비교에서 무시하는지 검증한다.
    /// - 검증 내용: isDirty false와 collection mode save 비활성화
    /// - 사전 조건: 의미상 동일하지만 Equatable로는 다른 baseline/current context
    /// - 기대 결과: 저장되지 않은 변경 indicator가 켜지지 않음
    func testIndicateUnsavedCollectionFilterChanges_withSemanticEquivalentContext_keepsSaveIndicatorDisabled() {
        let baseline = CollectionContext(
            query: "report",
            scopes: ["/VoyagerFixtures/Documents/../Documents", "/VoyagerFixtures/Notes"],
            excludedScopes: ["/VoyagerFixtures/Documents/Archive"],
            conditions: [
                makeSemanticCondition(propertyKey: "size", propertyLabel: "Size", values: [" 1024 "]),
                makeSemanticCondition(propertyKey: "kind", propertyLabel: "Kind", values: [" pdf "]),
            ],
        )
        var state = CollectionState()
        state.collectionSession.metadata.baseline = CollectionBaseline(context: baseline)
        state.collectionContext = CollectionContext(
            query: " report ",
            scopes: ["/VoyagerFixtures/Notes", "/VoyagerFixtures/Documents"],
            excludedScopes: ["/VoyagerFixtures/Documents/./Archive"],
            conditions: [
                makeSemanticCondition(propertyKey: "kind", propertyLabel: "File Kind", values: ["pdf"]),
                makeSemanticCondition(propertyKey: "size", propertyLabel: "File Size", values: ["1024"]),
            ],
        )

        XCTAssertFalse(state.isDirty)
        XCTAssertFalse(state.canSave(isCollectionMode: true))
    }

    // MARK: - RCL-002-open_saved_collection_legacy

    /// RCL-002-open_saved_collection_legacy: legacy single-file `.voycoll` fixture는 호환 모드로 열어야 한다.
    /// 패키지가 아닌 과거 단일 파일 payload를 실제 파일에서 읽어 migration metadata를 검증한다.
    /// - 검증 내용: legacy container, schema fallback, migration path, writeback 차단 사유
    /// - 사전 조건: `fixtures/fixtures/collections/legacy_schema_v1_collection.voycoll`을 sandbox로 복사해 사용
    /// - 기대 결과: legacy payload는 schema 1.0으로 정규화되며 version upgrade writeback은 차단됨
    func testOpenSavedCollection_withLegacySingleFileFixture_restoresCompatibilityMetadata() async throws {
        let sandbox = try CollectionFixtureSandbox.copyingFile(
            from: "fixtures/fixtures/collections/legacy_schema_v1_collection.voycoll",
        )
        defer { try? sandbox.cleanup() }

        let result = try await CollectionFileClient.liveValue.load(sandbox.fileURL)

        XCTAssertEqual(result.containerFormat, .legacySingleFile)
        XCTAssertEqual(result.file.id, "rcl-legacy-schema-v1-collection")
        XCTAssertEqual(result.file.query, "legacy report")
        XCTAssertEqual(result.file.schemaVersion, SchemaVersion(major: 1, minor: 0))
        XCTAssertNil(result.compatibility.sourceSchemaVersion)
        XCTAssertEqual(result.compatibility.migrationPath, [
            .legacySingleFileWithoutSchema,
            .definitionOnlyV1,
        ])
        XCTAssertFalse(result.compatibility.writeBackAllowed)
        XCTAssertEqual(result.compatibility.writeBackReason, .blockedLegacyVersionUpgrade)
    }
}

private let builtInReadOnlyFeedback = CollectionSaveFeedback(
    stage: .saveBlocked,
    category: .futureMinorReadOnly,
    title: "Built-In Collection Is Read-Only",
    message: "Voyager manages this built-in Collection automatically.",
    recoveryHint: "Choose Save As to create an editable copy.",
    isRetryable: false,
)

@MainActor
private func assertCaseVariantDestinationsAreReadOnly(
    _ selectedURLs: [URL],
    applicationSupportURL: URL,
) async {
    for selectedURL in selectedURLs {
        let payload = makeSavePayload(query: "protected case variant", snapshotItems: nil)
        let recorder = CollectionFileSaveRecorder()
        let store = TestStore(initialState: CollectionState()) {
            CollectionFeature()
        } withDependencies: {
            $0.fileManagerClient.urlsForDirectory = { _, _ in [applicationSupportURL] }
            $0.collectionSavePanelClient.defaultSaveDirectory = { _ in applicationSupportURL }
            $0.collectionSavePanelClient.presentSavePanel = { _ in selectedURL }
            $0.collectionFileClient.save = recorder.save
        }

        await store.send(.saveRequested(payload)) {
            $0.isSaving = true
            $0.pendingSaveContext = payload.context
            $0.pendingSave = makeSaveSnapshot(query: "protected case variant", snapshotItems: nil)
        }
        await store.receive(\.savePanelResponse) {
            $0.isSaving = false
            $0.pendingSave = nil
            $0.pendingSaveContext = nil
        }
        await store.receive(\.delegate.saveFeedback, builtInReadOnlyFeedback)

        XCTAssertEqual(recorder.invocationCount, 0)
        XCTAssertNil(recorder.lastSave)
    }
}

@MainActor
private struct CollectionSaveProtectionFixture {
    let sandboxURL: URL
    let canonicalURL: URL
    let symlinkURL: URL
    let aliasURL: URL
    let fileManagerClient: FileManagerClient

    init() throws {
        sandboxURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RCL002SaveProtection-\(UUID().uuidString)", isDirectory: true)
        let applicationSupportURL = sandboxURL.appendingPathComponent("Application Support", isDirectory: true)
        canonicalURL = BuiltInCollectionIdentity.recents.canonicalPackageURL(
            applicationSupportURL: applicationSupportURL,
        )
        try FileManager.default.createDirectory(at: canonicalURL, withIntermediateDirectories: true)
        symlinkURL = sandboxURL.appendingPathComponent("Recents Symlink.voycoll")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: canonicalURL)
        aliasURL = sandboxURL.appendingPathComponent("Recents Alias.voycoll")
        let bookmarkData = try canonicalURL.bookmarkData(options: .suitableForBookmarkFile)
        try URL.writeBookmarkData(bookmarkData, to: aliasURL)
        var client = FileManagerClient.liveValue
        client.urlsForDirectory = { _, _ in [applicationSupportURL] }
        fileManagerClient = client
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: sandboxURL)
    }

    func assertCanonicalLinksAreBlocked() async throws {
        for destinationURL in [symlinkURL, aliasURL] {
            let recorder = CollectionFileSaveRecorder()
            let store = TestStore(initialState: CollectionState()) {
                CollectionFeature()
            } withDependencies: {
                $0.fileManagerClient = fileManagerClient
                $0.collectionFileClient.save = recorder.save
            }

            await store.send(.saveToExisting(
                makeSavePayload(query: "protected filesystem link", snapshotItems: nil),
                destinationURL,
            ))
            await store.receive(\.delegate.saveFeedback, builtInReadOnlyFeedback)
            XCTAssertEqual(recorder.invocationCount, 0)
            XCTAssertFalse(store.state.isSaving)
        }
    }

    func assertCanonicalLinkTargetRemainsEditable() async throws {
        let userPackageURL = sandboxURL.appendingPathComponent("User Collection.voycoll", isDirectory: true)
        try FileManager.default.createDirectory(at: userPackageURL, withIntermediateDirectories: true)
        try FileManager.default.removeItem(at: canonicalURL)
        try FileManager.default.createSymbolicLink(at: canonicalURL, withDestinationURL: userPackageURL)

        let canonicalRecorder = CollectionFileSaveRecorder()
        let canonicalStore = TestStore(initialState: CollectionState()) {
            CollectionFeature()
        } withDependencies: {
            $0.fileManagerClient = fileManagerClient
            $0.collectionFileClient.save = canonicalRecorder.save
        }
        await canonicalStore.send(.saveToExisting(
            makeSavePayload(query: "protected canonical symlink", snapshotItems: nil),
            canonicalURL,
        ))
        await canonicalStore.receive(\.delegate.saveFeedback, builtInReadOnlyFeedback)
        XCTAssertEqual(canonicalRecorder.invocationCount, 0)

        let recorder = CollectionFileSaveRecorder()
        let store = TestStore(initialState: CollectionState()) {
            CollectionFeature()
        } withDependencies: {
            $0.fileManagerClient = fileManagerClient
            $0.collectionFileClient.save = recorder.save
        }

        await store.send(.saveToExisting(
            makeSavePayload(query: "editable user package", snapshotItems: nil),
            userPackageURL,
        )) {
            $0.isSaving = true
        }
        await store.receive(\.saveCompleted) {
            $0.isSaving = false
        }
        XCTAssertEqual(recorder.invocationCount, 1)
    }
}

private final class CollectionFileSaveRecorder: @unchecked Sendable {
    struct Saved: Equatable {
        let file: VoyagerCollectionFile
        let url: URL
    }

    private let saves = LockIsolated<[Saved]>([])

    var invocationCount: Int {
        saves.value.count
    }

    var lastSave: Saved? {
        saves.value.last
    }

    var save: @Sendable (VoyagerCollectionFile, URL) async throws -> Void {
        { [weak self] file, url in
            self?.saves.withValue {
                $0.append(Saved(file: file, url: url))
            }
        }
    }
}

private func reduce(
    _ state: inout CollectionState,
    action: CollectionAction,
) async -> [CollectionAction] {
    let effect = CollectionFeature().reduce(into: &state, action: action)
    var actions: [CollectionAction] = []
    for await action in effect.actions {
        actions.append(action)
    }
    return actions
}

private func draftRestore(from actions: [CollectionAction]) -> CollectionDraftRestorePayload? {
    for action in actions {
        if case let .delegate(.draftRestorePrepared(payload)) = action {
            return payload
        }
    }
    return nil
}

private func makeSemanticCondition(
    propertyKey: String,
    propertyLabel: String,
    values: [String],
) -> Condition {
    ConditionFixture.make(
        propertyKey: propertyKey,
        propertyLabel: propertyLabel,
        propertyType: "string",
        operatorCode: "eq",
        operatorLabel: "Equals",
        contract: .init(shape: .single, count: .fixed(1), input: .singleText),
        values: values,
    )
}

private func makeSavePayload(
    query: String,
    snapshotItems: [VoyagerShared.JSONValue]?,
) -> SaveRequestPayload {
    SaveRequestPayload(
        context: CollectionContext(
            query: query,
            scopes: ["/VoyagerFixtures/Documents"],
            excludedScopes: [],
            includeSubfolders: true,
            includeDirectories: false,
            conditions: [],
        ),
        isSearchLoading: false,
        isFiltersLoading: false,
        snapshotItems: snapshotItems,
        definitionFingerprint: "rcl-002-save-fingerprint",
        capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
        relevanceRoots: ["/VoyagerFixtures/Documents"],
        openedCompatibility: nil,
    )
}

private func makeSaveSnapshot(
    query: String,
    snapshotItems: [VoyagerShared.JSONValue]?,
) -> CollectionSaveSnapshot {
    CollectionSaveSnapshot(
        query: query,
        scopes: ["/VoyagerFixtures/Documents"],
        excludedScopes: [],
        includeSubfolders: true,
        includeDirectories: false,
        conditions: [],
        snapshotItems: snapshotItems,
        definitionFingerprint: "rcl-002-save-fingerprint",
        capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
        relevanceRoots: ["/VoyagerFixtures/Documents"],
    )
}
