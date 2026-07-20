import VoyagerFeaturesAccountAccess

actor AccessSnapshotRecorder {
    private var values: [AccessStatusSnapshot] = []

    func append(_ snapshot: AccessStatusSnapshot) {
        values.append(snapshot)
    }

    func snapshot() -> [AccessStatusSnapshot] {
        values
    }
}

enum AccessSnapshotClient {
    static func recording(
        recorder: AccessSnapshotRecorder,
        load snapshot: AccessStatusSnapshot? = nil,
    ) -> AccessStatusSnapshotClient {
        AccessStatusSnapshotClient(
            load: { snapshot },
            save: { snapshot in
                await recorder.append(snapshot)
            },
            remove: {},
        )
    }
}
