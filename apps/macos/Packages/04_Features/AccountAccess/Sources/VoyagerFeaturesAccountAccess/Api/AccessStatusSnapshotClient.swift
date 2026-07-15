import ComposableArchitecture
import Foundation
import VoyagerEntitiesAppPreferences
import VoyagerShared

public struct AccessStatusSnapshotClient: Sendable {
    var activate: @Sendable (_ sessionBindingID: UUID?, _ environment: GatewayEnvironment) async -> Int
    var load: @Sendable (_ sessionBindingID: UUID?, _ environment: GatewayEnvironment) async
        -> AccessStatusSnapshotEnvelope?
    var save: @Sendable (
        _ snapshot: AccessStatusSnapshot,
        _ sessionBindingID: UUID?,
        _ environment: GatewayEnvironment,
        _ generation: Int,
    ) async -> Void
    var remove: @Sendable (_ sessionBindingID: UUID?, _ environment: GatewayEnvironment, _ generation: Int) async
        -> Void

    init(
        activate: @escaping @Sendable (_ sessionBindingID: UUID?, _ environment: GatewayEnvironment) async -> Int,
        load: @escaping @Sendable (_ sessionBindingID: UUID?, _ environment: GatewayEnvironment) async
            -> AccessStatusSnapshotEnvelope?,
        save: @escaping @Sendable (
            _ snapshot: AccessStatusSnapshot,
            _ sessionBindingID: UUID?,
            _ environment: GatewayEnvironment,
            _ generation: Int,
        ) async -> Void,
        remove: @escaping @Sendable (
            _ sessionBindingID: UUID?,
            _ environment: GatewayEnvironment,
            _ generation: Int,
        ) async
            -> Void,
    ) {
        self.activate = activate
        self.load = load
        self.save = save
        self.remove = remove
    }

    init(store: AccessStatusSnapshotStore) {
        self.init(
            activate: { sessionBindingID, environment in
                await store.activate(sessionBindingID: sessionBindingID, gatewayBinding: environment.binding)
            },
            load: { sessionBindingID, environment in
                await store.load(sessionBindingID: sessionBindingID, gatewayBinding: environment.binding)
            },
            save: { snapshot, sessionBindingID, environment, generation in
                await store.save(
                    snapshot: snapshot,
                    sessionBindingID: sessionBindingID,
                    gatewayBinding: environment.binding,
                    generation: generation,
                )
            },
            remove: { sessionBindingID, environment, generation in
                await store.remove(
                    sessionBindingID: sessionBindingID,
                    gatewayBinding: environment.binding,
                    generation: generation,
                )
            },
        )
    }

    public init(
        activate: @escaping @Sendable () async -> Int,
        load: @escaping @Sendable () async -> AccessStatusSnapshot?,
        save: @escaping @Sendable (_ snapshot: AccessStatusSnapshot) async -> Void,
        remove: @escaping @Sendable () async -> Void,
    ) {
        self.init(
            activate: { _, _ in await activate() },
            load: { _, _ in
                guard let snapshot = await load() else { return nil }
                return AccessStatusSnapshotEnvelope(
                    sessionBindingID: nil,
                    gatewayBinding: "",
                    mutationGeneration: 0,
                    snapshot: snapshot,
                )
            },
            save: { snapshot, _, _, _ in
                await save(snapshot)
            },
            remove: { _, _, _ in
                await remove()
            },
        )
    }

    public init(
        load: @escaping @Sendable () async -> AccessStatusSnapshot?,
        save: @escaping @Sendable (_ snapshot: AccessStatusSnapshot) async -> Void,
        remove: @escaping @Sendable () async -> Void,
    ) {
        self.init(
            activate: { 0 },
            load: load,
            save: save,
            remove: remove,
        )
    }
}

struct AccessStatusSnapshotEnvelope: Codable, Equatable {
    static let currentSchemaVersion = 1

    let sessionBindingID: UUID?
    let gatewayBinding: String
    let schemaVersion: Int
    let mutationGeneration: Int
    let snapshot: AccessStatusSnapshot?
    let isLegacy: Bool

    init(
        sessionBindingID: UUID?,
        gatewayBinding: String,
        mutationGeneration: Int,
        snapshot: AccessStatusSnapshot?,
        isLegacy: Bool = false,
        schemaVersion: Int = Self.currentSchemaVersion,
    ) {
        self.sessionBindingID = sessionBindingID
        self.gatewayBinding = gatewayBinding
        self.schemaVersion = schemaVersion
        self.mutationGeneration = mutationGeneration
        self.snapshot = snapshot
        self.isLegacy = isLegacy
    }

    private enum CodingKeys: String, CodingKey {
        case sessionBindingID
        case gatewayBinding
        case schemaVersion
        case mutationGeneration
        case snapshot
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionBindingID = try container.decodeIfPresent(UUID.self, forKey: .sessionBindingID)
        gatewayBinding = try container.decode(String.self, forKey: .gatewayBinding)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        mutationGeneration = try container.decode(Int.self, forKey: .mutationGeneration)
        snapshot = try container.decodeIfPresent(AccessStatusSnapshot.self, forKey: .snapshot)
        isLegacy = schemaVersion != Self.currentSchemaVersion
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(sessionBindingID, forKey: .sessionBindingID)
        try container.encode(gatewayBinding, forKey: .gatewayBinding)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(mutationGeneration, forKey: .mutationGeneration)
        try container.encodeIfPresent(snapshot, forKey: .snapshot)
    }
}

actor AccessStatusSnapshotStore {
    private let userDefaults: UserDefaultsClient

    init(userDefaults: UserDefaultsClient) {
        self.userDefaults = userDefaults
    }

    func load(sessionBindingID: UUID?, gatewayBinding: String) -> AccessStatusSnapshotEnvelope? {
        guard let envelope = decodedEnvelope() else {
            let activated = currentEnvelope(
                sessionBindingID: sessionBindingID,
                gatewayBinding: gatewayBinding,
                mutationGeneration: 0,
            )
            persist(activated)
            return activated
        }
        guard !envelope.isLegacy else { return envelope }
        guard envelope.sessionBindingID == sessionBindingID, envelope.gatewayBinding == gatewayBinding else {
            let activated = currentEnvelope(
                sessionBindingID: sessionBindingID,
                gatewayBinding: gatewayBinding,
                mutationGeneration: envelope.mutationGeneration + 1,
            )
            persist(activated)
            return activated
        }
        return envelope
    }

    func activate(sessionBindingID: UUID?, gatewayBinding: String) -> Int {
        guard let envelope = decodedEnvelope() else {
            let activated = currentEnvelope(
                sessionBindingID: sessionBindingID,
                gatewayBinding: gatewayBinding,
                mutationGeneration: 0,
            )
            persist(activated)
            return activated.mutationGeneration
        }
        guard !envelope.isLegacy,
              envelope.sessionBindingID == sessionBindingID,
              envelope.gatewayBinding == gatewayBinding
        else {
            let activated = currentEnvelope(
                sessionBindingID: sessionBindingID,
                gatewayBinding: gatewayBinding,
                mutationGeneration: envelope.mutationGeneration + 1,
            )
            persist(activated)
            return activated.mutationGeneration
        }
        return envelope.mutationGeneration
    }

    func save(
        snapshot: AccessStatusSnapshot,
        sessionBindingID: UUID?,
        gatewayBinding: String,
        generation: Int,
    ) {
        guard let envelope = decodedEnvelope() else {
            persist(currentEnvelope(
                sessionBindingID: sessionBindingID,
                gatewayBinding: gatewayBinding,
                mutationGeneration: generation,
                snapshot: snapshot,
            ))
            return
        }
        if envelope.isLegacy {
            persist(currentEnvelope(
                sessionBindingID: sessionBindingID,
                gatewayBinding: gatewayBinding,
                mutationGeneration: generation,
                snapshot: snapshot,
            ))
            return
        }
        let identityMatches = envelope.sessionBindingID == sessionBindingID
            && envelope.gatewayBinding == gatewayBinding
        let advancesTombstone = envelope.snapshot == nil
            && generation > envelope.mutationGeneration
        guard (identityMatches && generation >= envelope.mutationGeneration) || advancesTombstone else { return }
        persist(currentEnvelope(
            sessionBindingID: sessionBindingID,
            gatewayBinding: gatewayBinding,
            mutationGeneration: generation,
            snapshot: snapshot,
        ))
    }

    func remove(sessionBindingID: UUID?, gatewayBinding: String, generation: Int) {
        guard let envelope = decodedEnvelope() else {
            persist(currentEnvelope(
                sessionBindingID: sessionBindingID,
                gatewayBinding: sessionBindingID == nil ? "" : gatewayBinding,
                mutationGeneration: generation + 1,
            ))
            return
        }
        if sessionBindingID == nil {
            persist(currentEnvelope(
                sessionBindingID: nil,
                gatewayBinding: "",
                mutationGeneration: max(envelope.mutationGeneration, generation) + 1,
            ))
            return
        }
        guard envelope.sessionBindingID == sessionBindingID, envelope.gatewayBinding == gatewayBinding else { return }
        persist(currentEnvelope(
            sessionBindingID: sessionBindingID,
            gatewayBinding: gatewayBinding,
            mutationGeneration: max(envelope.mutationGeneration, generation) + 1,
        ))
    }

    private func decodedEnvelope() -> AccessStatusSnapshotEnvelope? {
        guard let data = userDefaults.object(SettingsKeys.accessStatusSnapshot) as? Data else { return nil }
        if let envelope = try? JSONDecoder().decode(AccessStatusSnapshotEnvelope.self, from: data) {
            return envelope
        }
        guard let snapshot = try? JSONDecoder().decode(AccessStatusSnapshot.self, from: data) else { return nil }
        return AccessStatusSnapshotEnvelope(
            sessionBindingID: nil,
            gatewayBinding: "",
            mutationGeneration: 0,
            snapshot: snapshot,
            isLegacy: true,
            schemaVersion: 0,
        )
    }

    private func currentEnvelope(
        sessionBindingID: UUID?,
        gatewayBinding: String,
        mutationGeneration: Int,
        snapshot: AccessStatusSnapshot? = nil,
    ) -> AccessStatusSnapshotEnvelope {
        AccessStatusSnapshotEnvelope(
            sessionBindingID: sessionBindingID,
            gatewayBinding: gatewayBinding,
            mutationGeneration: mutationGeneration,
            snapshot: snapshot,
        )
    }

    private func persist(_ envelope: AccessStatusSnapshotEnvelope) {
        guard !Task.isCancelled else { return }
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        userDefaults.setObject(data, SettingsKeys.accessStatusSnapshot)
    }
}

extension AccessStatusSnapshotClient: DependencyKey {
    nonisolated public static var liveValue: AccessStatusSnapshotClient {
        @Dependency(\.userDefaultsClient)
        var userDefaults
        return AccessStatusSnapshotClient(store: AccessStatusSnapshotStore(userDefaults: userDefaults))
    }

    nonisolated public static var testValue: AccessStatusSnapshotClient {
        AccessStatusSnapshotClient(activate: { 0 }, load: { nil }, save: { _ in }, remove: {})
    }

    nonisolated public static var previewValue: AccessStatusSnapshotClient {
        testValue
    }
}

public extension DependencyValues {
    nonisolated var accessStatusSnapshotClient: AccessStatusSnapshotClient {
        get { self[AccessStatusSnapshotClient.self] }
        set { self[AccessStatusSnapshotClient.self] = newValue }
    }
}
