import ComposableArchitecture
import Foundation
import VoyagerShared

public struct ReleaseIdentityClient: Sendable {
    public var resolve: @Sendable (Date) -> ReleaseIdentity?

    public init(resolve: @escaping @Sendable (Date) -> ReleaseIdentity?) {
        self.resolve = resolve
    }
}

extension ReleaseIdentityClient: DependencyKey {
    public static let liveValue = Self(resolve: { now in
        try? AppVersionInfo.releaseIdentity(now: now)
    })

    public static let testValue = Self(resolve: { now in
        try? ReleaseIdentity(releasedAt: "1970-01-01T00:00:00Z", now: now)
    })
}

public extension DependencyValues {
    var releaseIdentityClient: ReleaseIdentityClient {
        get { self[ReleaseIdentityClient.self] }
        set { self[ReleaseIdentityClient.self] = newValue }
    }
}
