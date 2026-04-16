import Foundation

public struct ScopeFavoriteItem: Equatable, Sendable {
    public let name: String
    public let url: URL
    public let iconName: String

    public init(name: String, url: URL, iconName: String) {
        self.name = name
        self.url = url
        self.iconName = iconName
    }
}
