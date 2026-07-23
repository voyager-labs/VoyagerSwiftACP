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
    /// XPC Mach service name을 Info.plist에서 읽어 반환한다.
    ///
    /// 빌드 세팅에서 주입된 `XPC_MACH_SERVICE_NAME`이 반드시 존재해야 한다.
    /// 누락 시 잘못된 XPC 서비스에 연결하는 것을 방지하기 위해 fatalError로 종료한다 (fail-closed).
    /// `requireAppEnv()`와 동일한 정책: Info.plist raw 값만 신뢰한다.
    nonisolated public static func machServiceName(
        infoDictionary: [String: Any]? = Bundle.main.infoDictionary,
    ) -> String {
        guard let name = infoDictionary?["XPC_MACH_SERVICE_NAME"] as? String,
              !name.isEmpty
        else {
            fatalError("XPC_MACH_SERVICE_NAME missing from Info.plist — cannot resolve XPC service")
        }
        return name
    }
}
