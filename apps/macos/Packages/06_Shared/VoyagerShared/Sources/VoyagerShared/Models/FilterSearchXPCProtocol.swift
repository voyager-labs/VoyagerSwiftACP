import Foundation

@objc
public protocol FilterSearchXPCServiceProtocol {
    nonisolated func applyFilters(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void)
    nonisolated func querySearch(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void)
    nonisolated func recentSearch(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void)
    nonisolated func tagSearch(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void)
    nonisolated func warmUpAIModelCatalog(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void)
}

public enum FilterSearchXPCServiceConstants {
    nonisolated public static var machServiceName: String {
        Bundle.main.infoDictionary?["XPC_MACH_SERVICE_NAME"] as? String
            ?? "fm.voyager.Voyager.FilterSearchXPC" // legacy fallback
    }
}
