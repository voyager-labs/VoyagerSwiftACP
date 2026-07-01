// TODO(VOY-XXX): CheckoutURLClient는 auth가 아닌 billing concern이다.
// 별도 작업에서 빌링/커머스 패키지로 이동 필요.
// 이 테스크에서는 이동하지 않고 표식만 남긴다.

import AppKit
import ComposableArchitecture
import Foundation
import VoyagerShared

/// 체크아웃, 요금제, 고객지원 URL을 열거나 반환하는 TCA 의존성 클라이언트.
public struct CheckoutURLClient: Sendable {
    /// 브라우저에서 지정한 URL을 연다.
    public var openURL: @Sendable (URL) -> Void

    /// 체크아웃(구매) 페이지 URL을 반환한다.
    public var checkoutURL: @Sendable () -> URL

    /// 요금제 페이지 URL을 반환한다.
    public var pricingURL: @Sendable () -> URL

    /// 고객지원/도움 페이지 URL을 반환한다.
    public var supportURL: @Sendable () -> URL

    nonisolated public init(
        openURL: @escaping @Sendable (URL) -> Void,
        checkoutURL: @escaping @Sendable () -> URL,
        pricingURL: @escaping @Sendable () -> URL,
        supportURL: @escaping @Sendable () -> URL,
    ) {
        self.openURL = openURL
        self.checkoutURL = checkoutURL
        self.pricingURL = pricingURL
        self.supportURL = supportURL
    }
}

// MARK: - DependencyKey

extension CheckoutURLClient: DependencyKey {
    private static func stringValue(for key: String) -> String? {
        if let dotenvValue = EnvironmentLoader.stringValue(forKey: key),
           !dotenvValue.isEmpty
        {
            return dotenvValue
        }

        let infoValue = Bundle.main.infoDictionary?[key] as? String
        if let infoValue, !infoValue.isEmpty {
            return infoValue
        }

        return nil
    }

    private static func requiredWebURL(for key: String) -> URL {
        guard let value = stringValue(for: key) else {
            fatalError("Missing required URL config: \(key)")
        }

        return validatedWebURL(for: key, value: value)
    }

    private static func validatedWebURL(for key: String, value: String) -> URL {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false
        else {
            fatalError("Invalid required URL config: \(key)")
        }

        return url
    }

    private static func webRouteURL(path: String) -> URL {
        let baseKey = "PUBLIC_WEB_BASE_URL"
        let baseURL = requiredWebURL(for: baseKey)
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return baseURL.appendingPathComponent(cleanPath)
    }

    private static func testURL(path: String) -> URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "test.test"
        components.path = path

        guard let url = components.url else {
            fatalError("Invalid test URL path: \(path)")
        }

        return url
    }

    nonisolated public static var liveValue: CheckoutURLClient {
        CheckoutURLClient(
            openURL: { url in
                Task { @MainActor in
                    NSWorkspace.shared.open(url)
                }
            },
            checkoutURL: {
                webRouteURL(path: "/checkout")
            },
            pricingURL: {
                webRouteURL(path: "/pricing")
            },
            supportURL: {
                webRouteURL(path: "/support")
            },
        )
    }

    nonisolated public static var testValue: CheckoutURLClient {
        CheckoutURLClient(
            openURL: { _ in },
            checkoutURL: { testURL(path: "/checkout") },
            pricingURL: { testURL(path: "/pricing") },
            supportURL: { testURL(path: "/support") },
        )
    }

    nonisolated public static var previewValue: CheckoutURLClient {
        testValue
    }
}

// MARK: - DependencyValues

public extension DependencyValues {
    nonisolated var checkoutURLClient: CheckoutURLClient {
        get { self[CheckoutURLClient.self] }
        set { self[CheckoutURLClient.self] = newValue }
    }
}
