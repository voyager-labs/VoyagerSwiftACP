import Foundation

@objc
protocol FilterSearchXPCServiceProtocol {
    nonisolated func applyFilters(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void)
    nonisolated func querySearch(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void)
    nonisolated func recentSearch(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void)
    nonisolated func tagSearch(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void)
    nonisolated func warmUpAIModelCatalog(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void)
}

enum FilterSearchXPCServiceConstants {
    nonisolated static let machServiceName = "fm.voyager.Voyager.FilterSearchXPC"
}
