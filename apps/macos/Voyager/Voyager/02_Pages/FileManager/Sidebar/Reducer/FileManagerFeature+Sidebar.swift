import Foundation

extension FileManagerFeature {
    func matchSidebarToPath(
        state: inout State,
        path: String,
        favorites: [SidebarItems.FavoriteItem],
        locations: [SidebarItems.LocationItem],
    ) {
        state.selectedSidebarItem = {
            let computerName = navigationClient.computerName()
            if path == computerName {
                return locations.first(where: { $0.isComputer })?.name ?? path
            }
            if !path.hasPrefix("/") { return path }
            return favorites.first(where: { $0.url.path == path })?.name
                ?? locations.first(where: { $0.url.path == path })?.name
        }()
    }
}
