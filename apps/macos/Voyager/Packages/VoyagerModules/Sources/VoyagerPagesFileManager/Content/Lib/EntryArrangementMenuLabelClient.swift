import Foundation
import VoyagerEntitiesEntry

struct EntryArrangementMenuLabelClient: Sendable {
    var labelForPropertyKey: @Sendable (String) -> String
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
