import Foundation
@testable import VoyagerFeaturesBetaAccess

/// BetaAccess 테스트에서 자주 사용하는 BetaAccessClient 픽스처 모음.
/// 반복되는 클라이언트 생성 코드를 명명된 정적 헬퍼로 통합합니다.
enum BetaAccessClientFixture {
    /// 항상 성공 응답(`ok: true`)을 반환하는 클라이언트.
    static var success: BetaAccessClient {
        BetaAccessClient(verify: { _, _ in
            BetaAccessVerifyResponse(ok: true)
        })
    }

    /// 항상 실패 응답(`ok: false`)을 반환하는 클라이언트.
    static var notOk: BetaAccessClient {
        BetaAccessClient(verify: { _, _ in
            BetaAccessVerifyResponse(ok: false)
        })
    }

    /// 주어진 에러를 던지는 클라이언트.
    static func throwing(_ error: BetaAccessVerificationError) -> BetaAccessClient {
        BetaAccessClient(verify: { _, _ in throw error })
    }

    /// 주어진 코드로 `gatewayError`를 던지는 클라이언트.
    static func gatewayError(code: String) -> BetaAccessClient {
        BetaAccessClient(verify: { _, _ in
            throw BetaAccessVerificationError.gatewayError(code: code)
        })
    }
}
