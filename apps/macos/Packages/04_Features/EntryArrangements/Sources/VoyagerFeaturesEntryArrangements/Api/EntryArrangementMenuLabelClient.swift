import Foundation
import VoyagerEntitiesCollection

public struct EntryArrangementMenuLabelClient {
    public var labelForPropertyKey: (String) -> String
}

public extension EntryArrangementMenuLabelClient {
    static let live: EntryArrangementMenuLabelClient = {
        let registryClient = RegistryClient.live(snapshot: RegistrySnapshot.load())
        return EntryArrangementMenuLabelClient(
            labelForPropertyKey: { propertyKey in
                registryClient.label(for: propertyKey)
            }
        )
    }()
}
