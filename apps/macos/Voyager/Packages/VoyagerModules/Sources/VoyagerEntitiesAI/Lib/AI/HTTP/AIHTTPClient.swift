// Portions adapted from Swift AI SDK (Apache-2.0).
// Original: Sources/AISDKProviderUtils/PostToAPI.swift

import Foundation

/// Errors from AI HTTP requests.
public enum AIHTTPError: Error, Sendable, Equatable {
    case invalidURL(String)
    case httpError(statusCode: Int, body: String)
    case networkError(String)
    case timeout
    case cancelled
}

/// Voyager-safe timeout defaults (replaces upstream 24-hour defaults).
public enum AITimeoutDefaults {
    public static let connect: TimeInterval = 60
    public static let total: TimeInterval = 120
}

/// Simplified HTTP client for AI provider requests.
///
/// Sends JSON POST requests and returns raw data responses.
/// Supports custom headers, timeouts, and cancellation.
public struct AIHTTPClient: Sendable {
    public let session: URLSession

    public init(session: URLSession? = nil) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = AITimeoutDefaults.connect
        config.timeoutIntervalForResource = AITimeoutDefaults.total
        self.session = session ?? URLSession(configuration: config)
    }

    /// Sends a JSON POST request.
    public func post(
        url: String,
        headers: [String: String] = [:],
        body: some Encodable,
        timeout: TimeInterval = AITimeoutDefaults.total,
    ) async throws -> Data {
        guard let requestURL = URL(string: url) else {
            throw AIHTTPError.invalidURL(url)
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        request.httpBody = try encoder.encode(body)

        return try await execute(request: request, url: url)
    }

    /// Sends a raw data POST request.
    public func post(
        url: String,
        headers: [String: String] = [:],
        bodyData: Data,
        timeout: TimeInterval = AITimeoutDefaults.total,
    ) async throws -> Data {
        guard let requestURL = URL(string: url) else {
            throw AIHTTPError.invalidURL(url)
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        request.httpBody = bodyData
        return try await execute(request: request, url: url)
    }

    /// Streams response bytes for SSE consumption.
    public func stream(
        url: String,
        headers: [String: String] = [:],
        body: some Encodable,
        timeout: TimeInterval = AITimeoutDefaults.total,
    ) async throws -> URLSession.AsyncBytes {
        guard let requestURL = URL(string: url) else {
            throw AIHTTPError.invalidURL(url)
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        request.httpBody = try encoder.encode(body)

        let (bytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIHTTPError.networkError("Invalid response type")
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            var bodyText = ""
            for try await line in bytes {
                bodyText += String(decoding: [line], as: UTF8.self)
            }
            throw AIHTTPError.httpError(statusCode: httpResponse.statusCode, body: bodyText)
        }

        return bytes
    }

    private func execute(request: URLRequest, url _: String) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIHTTPError.networkError("Invalid response type")
            }

            guard (200 ... 299).contains(httpResponse.statusCode) else {
                let bodyText = String(data: data, encoding: .utf8) ?? ""
                throw AIHTTPError.httpError(statusCode: httpResponse.statusCode, body: bodyText)
            }

            return data
        } catch let error as AIHTTPError {
            throw error
        } catch is CancellationError {
            throw AIHTTPError.cancelled
        } catch {
            let nsError = error as NSError
            if nsError.code == NSURLErrorTimedOut {
                throw AIHTTPError.timeout
            }
            throw AIHTTPError.networkError(error.localizedDescription)
        }
    }
}
