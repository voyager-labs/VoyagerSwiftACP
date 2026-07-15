@testable import VoyagerFeaturesAccountAccess
import VoyagerShared
import XCTest

/// ACC-002: AccessStatusResponse backend wire-format 디코딩 및 toAccessStatus() 매핑 검증.
///
/// Backend `GET /access/status`가 반환하는 camelCase JSON을 AccessStatusResponse가 올바르게 디코딩하고,
/// `toAccessStatus()`가 raw status + productKey 조합을 canonical AccessStatus로 변환하는지 검증한다.
final class ACC002AccessStatusResponseCodingTests: XCTestCase {
    private var decoder: JSONDecoder = {
        let jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .iso8601
        return jsonDecoder
    }()

    // MARK: - Backend camelCase decode

    /// Backend JSON(camelCase)이 AccessStatusResponse로 올바르게 디코딩된다.
    func testBackendCamelCaseDecode() throws {
        let json = """
        {
            "hasAccess": true,
            "status": "active",
            "reason": "active_entitlement",
            "productKey": "trial",
            "currentPeriodEnd": "2026-07-05T00:00:00Z",
            "source": "polar"
        }
        """
        let data = Data(json.utf8)

        let response = try decoder.decode(AccessStatusResponse.self, from: data)

        XCTAssertTrue(response.hasAccess)
        XCTAssertEqual(response.status, "active")
        XCTAssertEqual(response.reason, "active_entitlement")
        XCTAssertEqual(response.productKey, "trial")
        XCTAssertNotNil(response.currentPeriodEnd)
        XCTAssertEqual(response.source, "polar")
    }

    /// optional 필드가 누락된 JSON이 nil로 디코딩된다.
    func testMissingOptionalFieldsDecodeAsNil() throws {
        let json = """
        {
            "hasAccess": false,
            "status": "none"
        }
        """
        let data = Data(json.utf8)

        let response = try decoder.decode(AccessStatusResponse.self, from: data)

        XCTAssertFalse(response.hasAccess)
        XCTAssertEqual(response.status, "none")
        XCTAssertNil(response.reason)
        XCTAssertNil(response.productKey)
        XCTAssertNil(response.currentPeriodEnd)
        XCTAssertNil(response.source)
    }

    /// currentPeriodEnd가 null인 JSON이 nil로 디코딩된다.
    func testNullCurrentPeriodEndDecodesAsNil() throws {
        let json = """
        {
            "hasAccess": true,
            "status": "active",
            "currentPeriodEnd": null
        }
        """
        let data = Data(json.utf8)

        let response = try decoder.decode(AccessStatusResponse.self, from: data)

        XCTAssertTrue(response.hasAccess)
        XCTAssertNil(response.currentPeriodEnd)
    }

    // MARK: - toAccessStatus() 매핑

    /// active + trial productKey → .trialActive
    func testToAccessStatusActiveTrial() {
        let response = AccessStatusResponse(
            hasAccess: true,
            status: "active",
            reason: "active_entitlement",
            productKey: "trial",
            source: "polar",
        )
        XCTAssertEqual(response.toAccessStatus(), .trialActive)
    }

    /// active + core productKey → .coreLicenseActive
    func testToAccessStatusActiveCore() {
        let response = AccessStatusResponse(
            hasAccess: true,
            status: "active",
            reason: "active_entitlement",
            productKey: "core",
            source: "polar",
        )
        XCTAssertEqual(response.toAccessStatus(), .coreLicenseActive)
    }

    /// active + lifetime productKey → .coreLicenseActive
    func testToAccessStatusActiveLifetime() {
        let response = AccessStatusResponse(
            hasAccess: true,
            status: "active",
            productKey: "lifetime",
        )
        XCTAssertEqual(response.toAccessStatus(), .coreLicenseActive)
    }

    /// active + null productKey → .coreLicenseActive (fallback)
    func testToAccessStatusActiveNullProductKey() {
        let response = AccessStatusResponse(
            hasAccess: true,
            status: "active",
            productKey: nil,
        )
        XCTAssertEqual(response.toAccessStatus(), .coreLicenseActive)
    }

    /// Backend canonical status는 hasAccess fallback보다 우선한다.
    func testToAccessStatusCanonicalStatuses() {
        let cases: [(String, AccessStatus)] = [
            ("core_license_active", .coreLicenseActive),
            ("internal_test_active", .internalTestActive),
            ("trial_active", .trialActive),
            ("trial_expired", .trialExpired),
            ("revoked", .revoked),
            ("refunded", .refunded),
            ("none", .none),
        ]

        for (status, expected) in cases {
            let response = AccessStatusResponse(hasAccess: false, status: status)
            XCTAssertEqual(response.toAccessStatus(), expected)
        }
    }

    /// revoked → .revoked
    func testToAccessStatusRevoked() {
        let response = AccessStatusResponse(
            hasAccess: false,
            status: "revoked",
            reason: "revoked_entitlement",
        )
        XCTAssertEqual(response.toAccessStatus(), .revoked)
    }

    /// refunded → .refunded
    func testToAccessStatusRefunded() {
        let response = AccessStatusResponse(
            hasAccess: false,
            status: "refunded",
            reason: "refunded_entitlement",
        )
        XCTAssertEqual(response.toAccessStatus(), .refunded)
    }

    /// expired + trial → .trialExpired
    func testToAccessStatusExpiredTrial() {
        let response = AccessStatusResponse(
            hasAccess: false,
            status: "expired",
            reason: "expired_entitlement",
            productKey: "trial",
        )
        XCTAssertEqual(response.toAccessStatus(), .trialExpired)
    }

    /// expired + non-trial → .none
    func testToAccessStatusExpiredNonTrial() {
        let response = AccessStatusResponse(
            hasAccess: false,
            status: "expired",
            productKey: "core",
        )
        XCTAssertEqual(response.toAccessStatus(), .none)
    }

    /// inactive → .none
    func testToAccessStatusInactive() {
        let response = AccessStatusResponse(
            hasAccess: false,
            status: "inactive",
            reason: "inactive_entitlement",
        )
        XCTAssertEqual(response.toAccessStatus(), .none)
    }

    /// past_due → .none
    func testToAccessStatusPastDue() {
        let response = AccessStatusResponse(
            hasAccess: false,
            status: "past_due",
            reason: "past_due_subscription",
        )
        XCTAssertEqual(response.toAccessStatus(), .none)
    }

    /// none → .none
    func testToAccessStatusNone() {
        let response = AccessStatusResponse(
            hasAccess: false,
            status: "none",
            reason: "no_entitlement",
        )
        XCTAssertEqual(response.toAccessStatus(), .none)
    }

    // MARK: - Round-trip encode/decode

    /// 동일 struct 인스턴스를 encode → decode했을 때 값이 보존된다.
    func testRoundTripEncodeDecode() throws {
        let original = AccessStatusResponse(
            hasAccess: true,
            status: "active",
            reason: "active_entitlement",
            productKey: "core",
            currentPeriodEnd: Date(timeIntervalSince1970: 1_800_000_000),
            source: "polar",
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(AccessStatusResponse.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    /// 기존 snapshot blob의 expiresAt 키를 currentPeriodEnd로 복원한다.
    func testAccessStatusSnapshotDecodesLegacyExpiresAt() throws {
        struct LegacySnapshot: Encodable {
            let status: AccessStatus
            let expiresAt: Date
            let fetchedAt: Date
        }

        let expiresAt = Date(timeIntervalSince1970: 1_900_000_000)
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let legacy = LegacySnapshot(
            status: .coreLicenseActive,
            expiresAt: expiresAt,
            fetchedAt: fetchedAt,
        )
        let data = try JSONEncoder().encode(legacy)

        let snapshot = try JSONDecoder().decode(AccessStatusSnapshot.self, from: data)

        XCTAssertEqual(snapshot.status, .coreLicenseActive)
        XCTAssertEqual(snapshot.currentPeriodEnd, expiresAt)
        XCTAssertEqual(snapshot.fetchedAt, fetchedAt)
    }

    func testSnapshotStorePreservesSameBindingAndClearsReplacement() async {
        let client = AccessStatusSnapshotClient(store: AccessStatusSnapshotStore(userDefaults: .testValue))
        let bindingA = UUID()
        let bindingB = UUID()
        let gatewayEnvironment = GatewayEnvironment(rawValue: "https://gateway.example.com")
        let snapshot = AccessStatusSnapshot(status: .coreLicenseActive)

        _ = await client.load(bindingA, gatewayEnvironment)
        await client.save(snapshot, bindingA, gatewayEnvironment, 3)

        let restored = await client.load(bindingA, gatewayEnvironment)
        XCTAssertEqual(restored?.snapshot, snapshot)
        XCTAssertEqual(restored?.sessionBindingID, bindingA)

        let replacement = await client.load(bindingB, gatewayEnvironment)
        XCTAssertNil(replacement?.snapshot)
        XCTAssertEqual(replacement?.sessionBindingID, bindingB)
        XCTAssertGreaterThan(replacement?.mutationGeneration ?? 0, 3)
    }

    /// ACC-002-check_entitlement_status: load 없이 첫 verified snapshot을 저장할 수 있다.
    /// 최초 sync가 load보다 먼저 완료되어도 현재 binding/gateway/generation envelope를 생성하는지 검증한다.
    /// - 검증 내용: 빈 storage의 save가 snapshot과 caller generation을 가진 envelope를 영속화한다.
    /// - 사전 조건: access status snapshot storage가 비어 있고 현재 binding과 gateway가 제공된다.
    /// - 기대 결과: 이후 load가 동일한 snapshot, binding, generation을 반환한다.
    func testSnapshotStoreSavesFirstVerifiedSnapshotWithoutPriorLoad() async {
        let client = AccessStatusSnapshotClient(store: AccessStatusSnapshotStore(userDefaults: .testValue))
        let binding = UUID()
        let gatewayEnvironment = GatewayEnvironment(rawValue: "https://gateway.example.com")
        let snapshot = AccessStatusSnapshot(status: .coreLicenseActive)

        await client.save(snapshot, binding, gatewayEnvironment, 3)

        let restored = await client.load(binding, gatewayEnvironment)
        XCTAssertEqual(restored?.snapshot, snapshot)
        XCTAssertEqual(restored?.sessionBindingID, binding)
        XCTAssertEqual(restored?.mutationGeneration, 3)
    }

    /// ACC-002-check_entitlement_status: envelope 없는 sign-out은 늦은 save를 막는 tombstone을 남긴다.
    /// snapshot을 아직 load하지 않은 sign-out 뒤에 이전 sync save가 도착해도 access fact가 복원되지 않는지 검증한다.
    /// - 검증 내용: binding remove가 generation+1 tombstone을 저장하고 더 낮은 generation save를 거부한다.
    /// - 사전 조건: storage가 비어 있고 binding의 remove generation은 4이며 늦은 save generation은 4다.
    /// - 기대 결과: 같은 binding을 다시 load해도 snapshot은 nil이고 mutation generation은 5다.
    func testSnapshotStoreNoEnvelopeRemoveRejectsLateStaleSave() async {
        let client = AccessStatusSnapshotClient(store: AccessStatusSnapshotStore(userDefaults: .testValue))
        let binding = UUID()
        let gatewayEnvironment = GatewayEnvironment(rawValue: "https://gateway.example.com")
        let snapshot = AccessStatusSnapshot(status: .coreLicenseActive)

        await client.remove(binding, gatewayEnvironment, 4)
        await client.save(snapshot, binding, gatewayEnvironment, 4)

        let restored = await client.load(binding, gatewayEnvironment)
        XCTAssertNil(restored?.snapshot)
        XCTAssertEqual(restored?.sessionBindingID, binding)
        XCTAssertEqual(restored?.mutationGeneration, 5)
    }

    /// ACC-002-check_entitlement_status: 저장된 snapshot은 같은 binding sign-out 뒤 제거된다.
    /// 정상 save 뒤 remove가 동일 binding의 snapshot을 tombstone으로 바꾸는지 검증한다.
    /// - 검증 내용: remove generation이 기존 envelope보다 높은 generation tombstone을 기록한다.
    /// - 사전 조건: binding/gateway가 일치하는 generation 3 verified snapshot이 저장되어 있다.
    /// - 기대 결과: 이후 load는 snapshot 없이 binding을 유지하고 generation은 4보다 크다.
    func testSnapshotStoreSaveThenRemoveLeavesBindingTombstone() async {
        let client = AccessStatusSnapshotClient(store: AccessStatusSnapshotStore(userDefaults: .testValue))
        let binding = UUID()
        let gatewayEnvironment = GatewayEnvironment(rawValue: "https://gateway.example.com")
        let snapshot = AccessStatusSnapshot(status: .coreLicenseActive)

        await client.save(snapshot, binding, gatewayEnvironment, 3)
        await client.remove(binding, gatewayEnvironment, 4)

        let restored = await client.load(binding, gatewayEnvironment)
        XCTAssertNil(restored?.snapshot)
        XCTAssertEqual(restored?.sessionBindingID, binding)
        XCTAssertGreaterThan(restored?.mutationGeneration ?? 0, 4)
    }

    /// ACC-002-check_entitlement_status: binding mismatch와 낮은 generation save는 현재 snapshot을 변경하지 않는다.
    /// 첫 save envelope가 생성된 뒤 기존 CAS guard가 계속 적용되는지 검증한다.
    /// - 검증 내용: 다른 binding 및 낮은 generation save가 현재 envelope를 덮어쓰지 않는다.
    /// - 사전 조건: binding A의 generation 5 snapshot이 저장되어 있고 binding B와 generation 4 save를 시도한다.
    /// - 기대 결과: binding A의 generation 5 snapshot만 유지된다.
    func testSnapshotStorePreservesMismatchAndGenerationGuardsAfterFirstSave() async {
        let client = AccessStatusSnapshotClient(store: AccessStatusSnapshotStore(userDefaults: .testValue))
        let bindingA = UUID()
        let bindingB = UUID()
        let gatewayEnvironment = GatewayEnvironment(rawValue: "https://gateway.example.com")
        let currentSnapshot = AccessStatusSnapshot(status: .coreLicenseActive)
        let staleSnapshot = AccessStatusSnapshot(status: .trialActive)

        await client.save(currentSnapshot, bindingA, gatewayEnvironment, 5)
        await client.save(staleSnapshot, bindingA, gatewayEnvironment, 4)
        await client.save(staleSnapshot, bindingB, gatewayEnvironment, 6)

        let restored = await client.load(bindingA, gatewayEnvironment)
        XCTAssertEqual(restored?.snapshot, currentSnapshot)
        XCTAssertEqual(restored?.sessionBindingID, bindingA)
        XCTAssertEqual(restored?.mutationGeneration, 5)
    }

    /// ACC-002-check_entitlement_status: 더 높은 generation의 새 binding은 tombstone을 교체할 수 있다.
    /// sign-out tombstone 뒤 새 account session이 저장될 때 이전 binding의 늦은 save가 새 snapshot을 되살리지 않는지 검증한다.
    /// - 검증 내용: tombstone보다 큰 generation의 binding B save만 허용하고 binding A의 늦은 save는 거부한다.
    /// - 사전 조건: binding A generation 4 snapshot을 remove해 generation 5 tombstone을 만들고 binding B generation 6 save를 시도한다.
    /// - 기대 결과: binding B snapshot이 저장되고 generation 4 binding A save 뒤에도 binding B envelope가 유지된다.
    func testSnapshotStoreHigherGenerationSaveReplacesTombstoneWithNewBinding() async {
        let client = AccessStatusSnapshotClient(store: AccessStatusSnapshotStore(userDefaults: .testValue))
        let bindingA = UUID()
        let bindingB = UUID()
        let gatewayEnvironment = GatewayEnvironment(rawValue: "https://gateway.example.com")
        let snapshotA = AccessStatusSnapshot(status: .coreLicenseActive)
        let snapshotB = AccessStatusSnapshot(status: .trialActive)

        await client.save(snapshotA, bindingA, gatewayEnvironment, 4)
        await client.remove(bindingA, gatewayEnvironment, 4)
        await client.save(snapshotB, bindingB, gatewayEnvironment, 6)
        await client.save(snapshotA, bindingA, gatewayEnvironment, 4)

        let restored = await client.load(bindingB, gatewayEnvironment)
        XCTAssertEqual(restored?.snapshot, snapshotB)
        XCTAssertEqual(restored?.sessionBindingID, bindingB)
        XCTAssertEqual(restored?.mutationGeneration, 6)
    }

    /// ACC-002-check_entitlement_status: nil sign-out tombstone도 더 높은 generation에서만 새 binding을 허용한다.
    /// signed-out tombstone이 남아 있어도 새 session은 더 높은 generation으로만 snapshot을 저장할 수 있는지 검증한다.
    /// - 검증 내용: generation 5 save는 nil tombstone generation 5에 거부되고 generation 6 save만 새 binding을 저장한다.
    /// - 사전 조건: storage가 비어 있고 nil binding sign-out remove generation은 4다.
    /// - 기대 결과: binding B generation 6 snapshot이 저장되고 같은 generation의 늦은 save는 tombstone을 교체하지 못한다.
    func testSnapshotStoreNilSignOutTombstoneRequiresHigherGenerationForNewBinding() async {
        let client = AccessStatusSnapshotClient(store: AccessStatusSnapshotStore(userDefaults: .testValue))
        let binding = UUID()
        let gatewayEnvironment = GatewayEnvironment(rawValue: "https://gateway.example.com")
        let staleSnapshot = AccessStatusSnapshot(status: .coreLicenseActive)
        let currentSnapshot = AccessStatusSnapshot(status: .trialActive)

        await client.remove(nil, GatewayEnvironment(rawValue: ""), 4)
        await client.save(staleSnapshot, binding, gatewayEnvironment, 5)
        await client.save(currentSnapshot, binding, gatewayEnvironment, 6)

        let restored = await client.load(binding, gatewayEnvironment)
        XCTAssertEqual(restored?.snapshot, currentSnapshot)
        XCTAssertEqual(restored?.sessionBindingID, binding)
        XCTAssertEqual(restored?.mutationGeneration, 6)
    }

    func testSnapshotStoreRejectsStaleSaveAndLateSaveAfterSignOut() async {
        let client = AccessStatusSnapshotClient(store: AccessStatusSnapshotStore(userDefaults: .testValue))
        let binding = UUID()
        let gatewayEnvironment = GatewayEnvironment(rawValue: "https://gateway.example.com")
        let snapshot = AccessStatusSnapshot(status: .coreLicenseActive)

        _ = await client.load(binding, gatewayEnvironment)
        await client.save(snapshot, binding, gatewayEnvironment, 4)
        await client.remove(binding, gatewayEnvironment, 4)
        await client.save(snapshot, binding, gatewayEnvironment, 4)
        await client.remove(nil, GatewayEnvironment(rawValue: ""), 5)
        await client.save(snapshot, binding, gatewayEnvironment, 6)

        let restored = await client.load(nil, GatewayEnvironment(rawValue: ""))
        XCTAssertNil(restored?.snapshot)
        XCTAssertNil(restored?.sessionBindingID)
        XCTAssertGreaterThan(restored?.mutationGeneration ?? 0, 5)
    }

    func testSnapshotStoreLoadsLegacyPayloadUntilCurrentSaveRewritesIt() async throws {
        let legacySnapshot = AccessStatusSnapshot(status: .trialActive)
        let legacyData = try JSONEncoder().encode(legacySnapshot)
        let storage = SnapshotStorage(initialData: legacyData)
        let client = AccessStatusSnapshotClient(store: AccessStatusSnapshotStore(userDefaults: storage.client))
        let binding = UUID()
        let gatewayEnvironment = GatewayEnvironment(rawValue: "https://gateway.example.com")

        let legacy = await client.load(binding, gatewayEnvironment)
        XCTAssertEqual(legacy?.snapshot, legacySnapshot)
        XCTAssertTrue(legacy?.isLegacy ?? false)

        await client.save(legacySnapshot, binding, gatewayEnvironment, 1)

        let rewritten = await client.load(binding, gatewayEnvironment)
        XCTAssertFalse(rewritten?.isLegacy ?? true)
        XCTAssertEqual(rewritten?.schemaVersion, AccessStatusSnapshotEnvelope.currentSchemaVersion)
    }

    /// ACC-002-check_entitlement_status: 재시작 뒤 새 identity activation은 tombstone generation을 계승해 늦은 save를 차단한다.
    /// - 검증 내용: process B activation이 새 binding/gateway의 generation을 reseed하고 process A의 늦은 save를 거부한다.
    /// - 사전 조건: process A가 높은 generation snapshot을 저장한 뒤 sign-out tombstone을 남기고, 두 client가 같은 storage를 공유한다.
    /// - 기대 결과: process B snapshot만 보존되고 same binding gateway 변경은 snapshot을 비우며 generation을 증가시킨다.
    func testSnapshotStoreActivationReseedsAcrossRestartAndPreservesIdentityGuards() async {
        let storage = SnapshotStorage()
        let processA = AccessStatusSnapshotClient(store: AccessStatusSnapshotStore(userDefaults: storage.client))
        let processB = AccessStatusSnapshotClient(store: AccessStatusSnapshotStore(userDefaults: storage.client))
        let bindingA = UUID()
        let bindingB = UUID()
        let gatewayA = GatewayEnvironment(rawValue: "https://gateway-a.example.com")
        let gatewayB = GatewayEnvironment(rawValue: "https://gateway-b.example.com")
        let gatewayC = GatewayEnvironment(rawValue: "https://gateway-c.example.com")
        let snapshotA = AccessStatusSnapshot(status: .coreLicenseActive)
        let snapshotB = AccessStatusSnapshot(status: .trialActive)

        let initialGeneration = await processA.activate(bindingA, gatewayA)
        XCTAssertEqual(initialGeneration, 0)
        await processA.save(snapshotA, bindingA, gatewayA, 50)
        await processA.remove(bindingA, gatewayA, 50)

        let reseededGeneration = await processB.activate(bindingB, gatewayB)
        XCTAssertEqual(reseededGeneration, 52)
        await processB.save(snapshotB, bindingB, gatewayB, reseededGeneration)
        await processA.save(snapshotA, bindingA, gatewayA, 50)

        let retained = await processB.load(bindingB, gatewayB)
        XCTAssertEqual(retained?.snapshot, snapshotB)
        XCTAssertEqual(retained?.mutationGeneration, reseededGeneration)

        let gatewayChangeGeneration = await processB.activate(bindingB, gatewayC)
        XCTAssertEqual(gatewayChangeGeneration, reseededGeneration + 1)
        let gatewayChanged = await processB.load(bindingB, gatewayC)
        XCTAssertNil(gatewayChanged?.snapshot)

        await processB.save(snapshotB, bindingB, gatewayC, gatewayChangeGeneration)
        let sameIdentityGeneration = await processB.activate(bindingB, gatewayC)
        XCTAssertEqual(sameIdentityGeneration, gatewayChangeGeneration)
        let preserved = await processB.load(bindingB, gatewayC)
        XCTAssertEqual(preserved?.snapshot, snapshotB)
    }

    /// ACC-002-check_entitlement_status: 기존 public snapshot client initializer는 activation generation 0을 유지한다.
    /// - 검증 내용: activate closure 없이 생성한 client가 generation 0을 반환한다.
    /// - 사전 조건: 기존 load/save/remove source form으로 생성한 client.
    /// - 기대 결과: activation generation이 0이다.
    func testLegacySnapshotClientInitializerDefaultsActivationGenerationToZero() async {
        let client = AccessStatusSnapshotClient(
            load: { nil },
            save: { _ in },
            remove: {},
        )

        let generation = await client.activate(UUID(), GatewayEnvironment(rawValue: "https://gateway.example.com"))

        XCTAssertEqual(generation, 0)
    }

    /// ACC-002-check_entitlement_status: 취소된 activation은 다른 binding snapshot을 바꾸지 않는다.
    /// - 검증 내용: 취소된 task가 store actor에서 activation을 수행해도 persist boundary가 write를 거부한다.
    /// - 사전 조건: binding B의 verified snapshot이 저장되어 있고 binding A activation task가 gate에서 취소된다.
    /// - 기대 결과: binding B envelope와 snapshot이 그대로 유지된다.
    func testCancelledActivationDoesNotReplaceExistingSnapshot() async {
        let storage = SnapshotStorage()
        let store = AccessStatusSnapshotStore(userDefaults: storage.client)
        let gate = CancellationGate()
        let bindingA = UUID()
        let bindingB = UUID()
        let gatewayBinding = "https://gateway.example.com"
        let snapshotB = AccessStatusSnapshot(status: .coreLicenseActive)

        await store.save(
            snapshot: snapshotB,
            sessionBindingID: bindingB,
            gatewayBinding: gatewayBinding,
            generation: 5,
        )
        let activationTask = Task {
            await gate.wait()
            return await store.activate(sessionBindingID: bindingA, gatewayBinding: gatewayBinding)
        }
        await gate.waitUntilWaiting()
        activationTask.cancel()
        await gate.resume()
        _ = await activationTask.value

        let retained = await store.load(sessionBindingID: bindingB, gatewayBinding: gatewayBinding)

        XCTAssertEqual(retained?.sessionBindingID, bindingB)
        XCTAssertEqual(retained?.mutationGeneration, 5)
        XCTAssertEqual(retained?.snapshot, snapshotB)
    }

    /// ACC-002-check_entitlement_status: 취소된 higher-generation save는 다른 binding tombstone을 바꾸지 않는다.
    /// - 검증 내용: 취소된 task가 store actor에서 higher-generation save를 수행해도 persist boundary가 tombstone 교체를 거부한다.
    /// - 사전 조건: binding B의 generation 6 tombstone이 저장되어 있고 binding A save task가 gate에서 취소된다.
    /// - 기대 결과: binding B tombstone의 identity, generation, nil snapshot이 유지된다.
    func testCancelledSaveDoesNotReplaceExistingTombstone() async {
        let storage = SnapshotStorage()
        let store = AccessStatusSnapshotStore(userDefaults: storage.client)
        let gate = CancellationGate()
        let bindingA = UUID()
        let bindingB = UUID()
        let gatewayBinding = "https://gateway.example.com"
        let snapshotA = AccessStatusSnapshot(status: .trialActive)
        let snapshotB = AccessStatusSnapshot(status: .coreLicenseActive)

        await store.save(
            snapshot: snapshotB,
            sessionBindingID: bindingB,
            gatewayBinding: gatewayBinding,
            generation: 5,
        )
        await store.remove(sessionBindingID: bindingB, gatewayBinding: gatewayBinding, generation: 5)
        let saveTask = Task {
            await gate.wait()
            await store.save(
                snapshot: snapshotA,
                sessionBindingID: bindingA,
                gatewayBinding: gatewayBinding,
                generation: 7,
            )
        }
        await gate.waitUntilWaiting()
        saveTask.cancel()
        await gate.resume()
        await saveTask.value

        let retained = await store.load(sessionBindingID: bindingB, gatewayBinding: gatewayBinding)

        XCTAssertEqual(retained?.sessionBindingID, bindingB)
        XCTAssertEqual(retained?.mutationGeneration, 6)
        XCTAssertNil(retained?.snapshot)
    }

    private final class SnapshotStorage: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Any?

        init(initialData: Data? = nil) {
            value = initialData
        }

        var client: UserDefaultsClient {
            UserDefaultsClient(
                bool: { _ in false },
                setBool: { _, _ in },
                string: { _ in nil },
                setString: { _, _ in },
                double: { _ in 0 },
                setDouble: { _, _ in },
                object: { [self] _ in
                    lock.lock()
                    defer { lock.unlock() }
                    return value
                },
                setObject: { [self] value, _ in
                    lock.lock()
                    defer { lock.unlock() }
                    self.value = value
                },
            )
        }
    }
}

private actor CancellationGate {
    private var waitingContinuation: CheckedContinuation<Void, Never>?
    private var resumeContinuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            resumeContinuation = continuation
            waitingContinuation?.resume()
            waitingContinuation = nil
        }
    }

    func waitUntilWaiting() async {
        guard resumeContinuation == nil else { return }
        await withCheckedContinuation { continuation in
            waitingContinuation = continuation
        }
    }

    func resume() {
        resumeContinuation?.resume()
        resumeContinuation = nil
    }
}
