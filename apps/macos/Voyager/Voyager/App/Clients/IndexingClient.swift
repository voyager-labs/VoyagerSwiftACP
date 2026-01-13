import ComposableArchitecture
import Foundation
import Logging
import SwiftDotenv

private struct IndexingRequestPayload: Encodable {
    let paths: [String]
}

struct IndexingClient: Sendable {
    // TODO: VOY-88 정식 인덱싱 엔드포인트 구현 이후 요청 경로와 인덱싱 패스를 수정한다.
    var start: @Sendable (_ paths: [String]) async -> Void

    nonisolated init(start: @escaping @Sendable (_ paths: [String]) async -> Void) {
        self.start = start
    }
}

extension IndexingClient: DependencyKey {
    nonisolated static var liveValue: IndexingClient {
        let logger = Logger(label: "Voyager")
        return IndexingClient(start: { paths in
            guard !paths.isEmpty else { return }

            let request = await MainActor.run { () -> URLRequest? in
                let baseURL = Dotenv.publicBackendURL
                let url = baseURL.appendingPathComponent("api/files/indexing")
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try? JSONEncoder().encode(IndexingRequestPayload(paths: paths))
                return request
            }

            guard let request else {
                logger.warning("Indexing request build failed.")
                return
            }
            logger.info("Indexing request started.")
            let task = URLSession.shared.dataTask(with: request)
            task.resume()
        })
    }

    nonisolated static var testValue: IndexingClient {
        IndexingClient(start: { _ in })
    }

    nonisolated static var previewValue: IndexingClient {
        IndexingClient(start: { _ in })
    }
}

extension DependencyValues {
    nonisolated var indexingClient: IndexingClient {
        get { self[IndexingClient.self] }
        set { self[IndexingClient.self] = newValue }
    }
}
