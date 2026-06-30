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
    public var checkoutURL: @Sendable () throws -> URL

    /// 요금제 페이지 URL을 반환한다.
    public var pricingURL: @Sendable () throws -> URL

    /// 고객지원/도움 페이지 URL을 반환한다.
    public var supportURL: @Sendable () throws -> URL

    /// 계정(billing portal) 페이지 URL을 반환한다.
    public var accountURL: @Sendable () -> URL

    nonisolated public init(
        openURL: @escaping @Sendable (URL) -> Void,
        checkoutURL: @escaping @Sendable () throws -> URL,
        pricingURL: @escaping @Sendable () throws -> URL,
        supportURL: @escaping @Sendable () throws -> URL,
        accountURL: @escaping @Sendable () -> URL,
    ) {
        self.openURL = openURL
        self.checkoutURL = checkoutURL
        self.pricingURL = pricingURL
        self.supportURL = supportURL
        self.accountURL = accountURL
    }
}

// MARK: - DependencyKey

extension CheckoutURLClient: DependencyKey {
    // swiftlint:disable:next force_unwrapping
    private static let neutralBaseURL = URL(string: "https://example.invalid")!

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

    private static func directURL(for key: String) -> URL? {
        stringValue(for: key).flatMap(URL.init(string:))
    }

    private static func fallbackURL(directKey: String, baseKey: String, path: String) -> URL {
        if let directURL = directURL(for: directKey) {
            return directURL
        }

        let baseURL = stringValue(for: baseKey).flatMap(URL.init(string:)) ?? neutralBaseURL
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return baseURL.appendingPathComponent(cleanPath)
    }

    private static func requiredWebURL(for key: String) throws -> URL {
        guard let value = stringValue(for: key) else {
            throw AccessError.notConfigured
        }

        return try validatedWebURL(for: key, value: value)
    }

    nonisolated static func validatedWebURL(for _: String, value: String) throws -> URL {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false
        else {
            throw AccessError.notConfigured
        }

        return url
    }

    private static func webRouteURL(path: String) throws -> URL {
        let baseKey = "PUBLIC_WEB_BASE_URL"
        let baseURL = try requiredWebURL(for: baseKey)
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
                try webRouteURL(path: "/checkout")
            },
            pricingURL: {
                try webRouteURL(path: "/pricing")
            },
            supportURL: {
                try webRouteURL(path: "/support")
            },
            accountURL: {
                fallbackURL(
                    directKey: "VOYAGER_ACCOUNT_URL",
                    baseKey: "VOYAGER_WEB_BASE_URL",
                    path: "/account",
                )
            },
        )
    }

    nonisolated public static var testValue: CheckoutURLClient {
        CheckoutURLClient(
            openURL: { _ in },
            checkoutURL: { testURL(path: "/checkout") },
            pricingURL: { testURL(path: "/pricing") },
            supportURL: { testURL(path: "/support") },
            accountURL: { testURL(path: "/account") },
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
