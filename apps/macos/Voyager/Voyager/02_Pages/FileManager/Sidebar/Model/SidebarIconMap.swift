import Foundation

struct SidebarIconMap: Sendable {
    let directory: FileManager.SearchPathDirectory
    let domain: FileManager.SearchPathDomainMask
    let iconName: String
}
