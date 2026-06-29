import Foundation

public enum DefaultFileViewerStatus: Sendable, Equatable {
    case voyagerIsDefault
    case finderIsDefault
    case otherIsDefault(appBundleID: String, appDisplayName: String)
    case unknown
}
