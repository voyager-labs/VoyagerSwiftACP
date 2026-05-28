import VoyagerFeaturesLicenseAuth

actor LicenseAuthSnapshotRecorder {
    private var values: [LicenseAuthStatusSnapshot] = []

    func append(_ snapshot: LicenseAuthStatusSnapshot) {
        values.append(snapshot)
    }

    func snapshot() -> [LicenseAuthStatusSnapshot] {
        values
    }
}

enum LicenseAuthSnapshotClient {
    static func recording(
        recorder: LicenseAuthSnapshotRecorder,
        load snapshot: LicenseAuthStatusSnapshot? = nil,
    ) -> LicenseAuthStatusSnapshotClient {
        LicenseAuthStatusSnapshotClient(
            load: { snapshot },
            save: { snapshot in
                await recorder.append(snapshot)
            },
            remove: {},
        )
    }
}
