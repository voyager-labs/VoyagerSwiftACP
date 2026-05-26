import ComposableArchitecture
import Foundation
import IOKit
import SwiftDotenv
import VoyagerShared

public struct BetaAccessClient: Sendable {
    public var verify: @Sendable (_ email: String, _ token: String) async throws -> BetaAccessVerifyResponse

    public nonisolated init(
        verify: @escaping @Sendable (_ email: String, _ token: String) async throws -> BetaAccessVerifyResponse,
    ) {
        self.verify = verify
    }
}

public extension BetaAccessClient {
    nonisolated static var mockResponse: BetaAccessVerifyResponse {
        BetaAccessVerifyResponse(ok: true)
    }

    nonisolated static var mock: BetaAccessClient {
        BetaAccessClient(verify: { _, _ in
            mockResponse
        })
    }
}

extension BetaAccessClient: DependencyKey {
    public nonisolated static var liveValue: BetaAccessClient {
        BetaAccessClient(verify: { email, token in
            try await verifyBetaAccess(email: email, token: token)
        })
    }

    public nonisolated static var testValue: BetaAccessClient { .mock }
    public nonisolated static var previewValue: BetaAccessClient { .mock }
}

public extension DependencyValues {
    nonisolated var betaAccessClient: BetaAccessClient {
        get { self[BetaAccessClient.self] }
        set { self[BetaAccessClient.self] = newValue }
    }
}

private func verifyBetaAccess(email: String, token: String) async throws -> BetaAccessVerifyResponse {
    if ProcessInfo.processInfo.environment["VOYAGER_ONBOARDING_MOCK_BETA"] == "1" {
        return BetaAccessVerifyResponse(ok: true)
    }

    guard let urlString = Dotenv["PUBLIC_GATEWAY_URL"]?.stringValue,
          !urlString.isEmpty,
          let baseURL = URL(string: urlString)
    else {
        throw BetaAccessVerificationError.gatewayError(code: "invalid_gateway_url")
    }
    let url = baseURL.appendingPathComponent("auth/verify-cbt")
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let deviceId: String
    do {
        deviceId = try DeviceIdentifier.current()
    } catch {
        throw BetaAccessVerificationError.deviceIdUnavailable
    }

    let payload = BetaAccessVerifyRequest(
        email: email,
        deviceId: deviceId,
        appVersion: AppVersionInfo.shortVersion,
        osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
    )

    do {
        request.httpBody = try JSONEncoder().encode(payload)
    } catch {
        throw BetaAccessVerificationError.invalidRequest
    }

    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BetaAccessVerificationError.networkError
        }

        if (200 ..< 300).contains(http.statusCode) {
            do {
                return try JSONDecoder().decode(BetaAccessVerifyResponse.self, from: data)
            } catch {
                throw BetaAccessVerificationError.decodingError
            }
        }

        if let errorResponse = try? JSONDecoder().decode(BetaAccessErrorResponse.self, from: data) {
            throw BetaAccessVerificationError.gatewayError(code: errorResponse.error)
        }

        throw BetaAccessVerificationError.networkError
    } catch let error as BetaAccessVerificationError {
        throw error
    } catch {
        throw BetaAccessVerificationError.networkError
    }
}

private enum DeviceIdentifier {
    static func current() throws -> String {
        guard let uuid = platformUUID() else {
            throw BetaAccessVerificationError.deviceIdUnavailable
        }
        return uuid
    }

    private static func platformUUID() -> String? {
        let matching = IOServiceMatching("IOPlatformExpertDevice")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        guard let uuid = IORegistryEntryCreateCFProperty(
            service,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0,
        )?.takeRetainedValue() as? String else {
            return nil
        }
        return uuid
    }
}
