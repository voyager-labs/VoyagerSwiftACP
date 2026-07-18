import ComposableArchitecture
import Foundation

@ObservableState
public struct UpdaterState: Equatable {
    public var isAccessEligible = false
    public var updateStatus: String?
    public var updatesThrough: Date?
    public var didConfigure = false
    public var didStartAtLaunch = false

    public init(
        isAccessEligible: Bool = false,
        updateStatus: String? = nil,
        updatesThrough: Date? = nil,
        didConfigure: Bool = false,
        didStartAtLaunch: Bool = false,
    ) {
        self.isAccessEligible = isAccessEligible
        self.updateStatus = updateStatus
        self.updatesThrough = updatesThrough
        self.didConfigure = didConfigure
        self.didStartAtLaunch = didStartAtLaunch
    }
}
