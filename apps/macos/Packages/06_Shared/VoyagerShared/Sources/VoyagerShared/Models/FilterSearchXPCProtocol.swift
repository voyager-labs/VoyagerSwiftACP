import Foundation

@objc
public protocol FilterSearchXPCServiceProtocol {
    nonisolated func applyFilters(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void)
    nonisolated func querySearch(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void)
    nonisolated func recentSearch(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void)
    nonisolated func tagSearch(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void)
}

public enum FilterSearchXPCServiceConstants {
    nonisolated public static let machServiceName = "fm.voyager.Voyager.FilterSearchXPC"
}
