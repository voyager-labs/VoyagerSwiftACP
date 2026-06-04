import Foundation
import VoyagerShared

enum CollectionFilterResolution {
    static func resolve(
        file: VoyagerCollectionFile,
        registryClient: RegistryClient,
    ) -> AppliedFiltersUtils.ResolutionResult {
        file.resolveCollectionFilters(registryClient: registryClient)
    }
}
