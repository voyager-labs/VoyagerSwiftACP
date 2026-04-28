import Foundation

struct EntryArrangementMenuLabelClient {
    var labelForPropertyKey: (String) -> String
}

extension EntryArrangementMenuLabelClient {
    static let live: EntryArrangementMenuLabelClient = {
        let registryClient = RegistryClient.live(snapshot: RegistrySnapshot.load())
        return EntryArrangementMenuLabelClient(
            labelForPropertyKey: { propertyKey in
                registryClient.label(for: propertyKey)
            },
        )
    }()
}
