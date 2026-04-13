import Foundation
import VoyagerEntitiesEntry

struct EntryArrangementMenuLabelClient {
    var labelForPropertyKey: (String) -> String
}

extension EntryArrangementMenuLabelClient {
    static let live: EntryArrangementMenuLabelClient = {
        let registryClient = RegistryClient.liveValue
        return EntryArrangementMenuLabelClient(
            labelForPropertyKey: { propertyKey in
                registryClient.label(for: propertyKey)
            },
        )
    }()
}
