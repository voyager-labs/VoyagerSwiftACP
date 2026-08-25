import ComposableArchitecture
import Darwin
import Foundation

public enum StartPageDirectoryAvailability: Equatable, Sendable {
    case availableDirectory
    case missing
    case nonDirectory
    case permissionDenied
    case cloudPlaceholder
}

public struct StartPageAvailabilityClient: Sendable {
    public var probeDirectory: @Sendable (String) -> StartPageDirectoryAvailability

    public init(
        _ probeDirectory: @escaping @Sendable (String) -> StartPageDirectoryAvailability,
    ) {
        self.probeDirectory = probeDirectory
    }
}

extension StartPageAvailabilityClient: DependencyKey {
    nonisolated public static var liveValue: StartPageAvailabilityClient {
        StartPageAvailabilityClient { path in
            let url = URL(fileURLWithPath: path)
            do {
                let values = try url.resourceValues(forKeys: [
                    .isUbiquitousItemKey,
                    .ubiquitousItemDownloadingStatusKey,
                ])
                let downloadingStatus =
                    values.allValues[.ubiquitousItemDownloadingStatusKey] as? URLUbiquitousItemDownloadingStatus
                if values.isUbiquitousItem == true, downloadingStatus == .notDownloaded {
                    return .cloudPlaceholder
                }
            } catch {
                if error.isPermissionDenied {
                    return .permissionDenied
                }
            }

            var statBuffer = stat()
            let statResult = path.withCString { stat($0, &statBuffer) }
            guard statResult == 0 else {
                return errno == EACCES || errno == EPERM ? .permissionDenied : .missing
            }
            guard (statBuffer.st_mode & S_IFMT) == S_IFDIR else { return .nonDirectory }
            return .availableDirectory
        }
    }

    nonisolated public static var testValue: StartPageAvailabilityClient {
        StartPageAvailabilityClient { _ in
            fatalError("StartPageAvailabilityClient is unimplemented")
        }
    }

    nonisolated public static var previewValue: StartPageAvailabilityClient {
        StartPageAvailabilityClient { _ in .missing }
    }
}

public extension DependencyValues {
    nonisolated var startPageAvailabilityClient: StartPageAvailabilityClient {
        get { self[StartPageAvailabilityClient.self] }
        set { self[StartPageAvailabilityClient.self] = newValue }
    }
}

public enum StartPageFallbackReason: Equatable, Sendable {
    case missing
    case nonDirectory
    case permissionDenied
    case cloudPlaceholder

    public init(availability: StartPageDirectoryAvailability) {
        switch availability {
        case .missing:
            self = .missing
        case .nonDirectory:
            self = .nonDirectory
        case .permissionDenied:
            self = .permissionDenied
        case .cloudPlaceholder:
            self = .cloudPlaceholder
        case .availableDirectory:
            preconditionFailure("Available directories do not produce a fallback reason")
        }
    }
}

public struct StartPageResolution: Equatable, Sendable {
    public let effectiveStartPage: StartPage
    public let fallbackReason: StartPageFallbackReason?

    public init(
        effectiveStartPage: StartPage,
        fallbackReason: StartPageFallbackReason? = nil,
    ) {
        self.effectiveStartPage = effectiveStartPage
        self.fallbackReason = fallbackReason
    }
}

public enum StartPageResolver {
    public static func resolve(_ startPage: StartPage) -> StartPageResolution {
        @Dependency(\.startPageAvailabilityClient) var availabilityClient

        switch startPage {
        case .home:
            return StartPageResolution(effectiveStartPage: .home)
        case let .directory(path):
            let availability = availabilityClient.probeDirectory(path)
            guard availability == .availableDirectory else {
                return StartPageResolution(
                    effectiveStartPage: .home,
                    fallbackReason: StartPageFallbackReason(availability: availability),
                )
            }
            return StartPageResolution(effectiveStartPage: .directory(path))
        }
    }
}

private extension Error {
    var isPermissionDenied: Bool {
        let nsError = self as NSError
        if nsError.domain == NSPOSIXErrorDomain {
            return nsError.code == EACCES || nsError.code == EPERM
        }
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoPermissionError
    }
}
