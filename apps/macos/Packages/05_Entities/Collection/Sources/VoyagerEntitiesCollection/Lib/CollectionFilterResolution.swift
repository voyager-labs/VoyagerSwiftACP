import Foundation
import VoyagerShared

enum CollectionFilterResolution {
    static func resolve(
        file: VoyagerCollectionFile,
        registryClient: RegistryClient,
    ) -> AppliedFilterResolver.ResolutionResult {
        file.resolveCollectionFilters(registryClient: registryClient)
    }
}
