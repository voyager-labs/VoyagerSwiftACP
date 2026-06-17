// TODO(VOY-XXX): CheckoutURLClient는 auth가 아닌 billing concern이다.
// 별도 작업에서 빌링/커머스 패키지로 이동 필요.
// 이 테스크에서는 이동하지 않고 표식만 남긴다.

import AppKit
import ComposableArchitecture
import Foundation

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
    // swiftlint:disable:next force_unwrapping
    private static let neutralBaseURL = URL(string: "https://example.invalid")!

    private static func stringValue(for key: String) -> String? {
        let environment = ProcessInfo.processInfo.environment[key]
        if let environment, !environment.isEmpty {
            return environment
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

    nonisolated public static var liveValue: CheckoutURLClient {
        CheckoutURLClient(
            openURL: { url in
                Task { @MainActor in
                    NSWorkspace.shared.open(url)
                }
            },
            checkoutURL: {
                fallbackURL(
                    directKey: "VOYAGER_CHECKOUT_URL",
                    baseKey: "VOYAGER_WEB_BASE_URL",
                    path: "/checkout",
                )
            },
            pricingURL: {
                fallbackURL(
                    directKey: "VOYAGER_PRICING_URL",
                    baseKey: "VOYAGER_WEB_BASE_URL",
                    path: "/pricing",
                )
            },
            supportURL: {
                fallbackURL(
                    directKey: "VOYAGER_SUPPORT_URL",
                    baseKey: "VOYAGER_WEB_BASE_URL",
                    path: "/support",
                )
            },
        )
    }

    // swiftlint:disable force_unwrapping
    nonisolated public static var testValue: CheckoutURLClient {
        CheckoutURLClient(
            openURL: { _ in },
            checkoutURL: { URL(string: "http://test.test/checkout")! },
            pricingURL: { URL(string: "http://test.test/pricing")! },
            supportURL: { URL(string: "http://test.test/support")! },
        )
    }

    // swiftlint:enable force_unwrapping

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
