import Foundation

extension FileManagerFeature {
    func makeWindowTitle(for path: String) -> String {
        if path == "/" {
            return sidebarClient.computerName()
        }
        if path == sidebarClient.computerName() {
            return path
        }
        return entryClient.displayName(path)
    }

    static func makeWindowTitle(for path: String) -> String {
        let sidebarClient = SidebarClient.liveValue
        if path == "/" {
            return sidebarClient.computerName()
        }
        if path == sidebarClient.computerName() {
            return path
        }
        return EntryClient.liveValue.displayName(path)
    }

    func matchSidebarToPath(
        state: inout State,
        path: String,
        favorites: [SidebarUtils.FavoriteItem],
        locations: [SidebarUtils.LocationItem],
    ) {
        state.selectedSidebarItem = {
            let computerName = sidebarClient.computerName()
            if path == computerName {
                return locations.first(where: { $0.isComputer })?.name ?? path
            }
            if !path.hasPrefix("/") { return path }
            return favorites.first(where: { $0.url.path == path })?.name
                ?? locations.first(where: { $0.url.path == path })?.name
        }()
    }
}
