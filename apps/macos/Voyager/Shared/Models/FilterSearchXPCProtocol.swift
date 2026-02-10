import Foundation

@objc
protocol FilterSearchXPCServiceProtocol {
    func applyFilters(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void)
    func querySearch(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void)
}

enum FilterSearchXPCServiceConstants {
    static let machServiceName = "fm.voyager.Voyager.FilterSearchXPC"
}
