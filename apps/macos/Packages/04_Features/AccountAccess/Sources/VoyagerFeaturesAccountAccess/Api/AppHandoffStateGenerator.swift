import Foundation
import Security

/// CSRF 방지용 고엔트로피 state 파라미터 생성기.
/// RFC 6749 §10.12 권고에 따라 URL-safe 무작위 문자열을 생성한다.
public enum AppHandoffStateGenerator {
    /// 32바이트 암호학적 난수로 URL-safe 문자열을 생성한다.
    /// 결과는 `[A-Za-z0-9._~-]{1,256}` 패턴을 만족한다.
    public static func generate() -> String {
        let byteCount = 32
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
