import Foundation
@testable import VoyagerEntitiesEntry
import XCTest

final class EntryLoadingInstrumentationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var endedIntervals: [EntryLoadingInstrumentation.Interval] = []
    private var latestWorkCounts = EntryLoadingInstrumentation.WorkCounts()

    lazy var instrumentation = EntryLoadingInstrumentation(
        onBegin: { _, _ in },
        onEnd: { [weak self] interval, _, workCounts in
            self?.lock.withLock {
                self?.endedIntervals.append(interval)
                self?.latestWorkCounts = workCounts
            }
        },
    )

    var intervalNames: [String] {
        lock.withLock { endedIntervals.map(\.rawValue) }
    }

    var workCounts: EntryLoadingInstrumentation.WorkCounts {
        lock.withLock { latestWorkCounts }
    }
}

enum EntryLoadingBenchmark {
    private static let environmentKey = "VOYAGER_ENTRY_LOADING_BENCHMARK"
    private static let sampleCount = 20

    static func runIfEnabled() async throws {
        guard ProcessInfo.processInfo.environment[environmentKey] == "1" else {
            throw XCTSkip("Set \(environmentKey)=1 to run the serial performance benchmark.")
        }

        let fixture = try Fixture.make(entryCount: 1000)
        defer { fixture.remove() }

        let primarySamples = try await samples(for: fixture.directory, priority: .none, count: sampleCount)
        let spotlightSamples = try await samples(for: fixture.directory, priority: .active([.spotlight]), count: 1)
        let tagSamples = try await samples(for: fixture.directory, priority: .active([.tags]), count: 1)

        let report = Report(
            sampleCount: primarySamples.count,
            firstBatchMilliseconds: Percentiles(primarySamples.map(\.firstBatchMilliseconds)),
            coreCompleteMilliseconds: Percentiles(primarySamples.map(\.coreCompleteMilliseconds)),
            workCounts: primarySamples.map(\.workCounts),
            informationalPriorityMilliseconds: .init(
                spotlight: spotlightSamples.map(\.coreCompleteMilliseconds),
                tags: tagSamples.map(\.coreCompleteMilliseconds),
            ),
        )
        let data = try JSONEncoder().encode(report)
        print("ENTRY_LOADING_BENCHMARK_JSON=\(String(decoding: data, as: UTF8.self))")
    }

    private static func samples(
        for directory: URL,
        priority: EntryMetadataPriority,
        count: Int,
    ) async throws -> [Sample] {
        let clock = ContinuousClock()
        let client = EntryLoadingClient.liveValue

        return try await (0 ..< count).asyncMap { _ in
            let startedAt = clock.now
            var firstBatchMilliseconds: Double?
            var coreCompleteMilliseconds: Double?
            var workCounts = WorkCounts()

            for try await event in client.loadItems(directory, true, priority) {
                switch event {
                case let .coreBatch(items, _):
                    workCounts.coreEntries += items.count
                    if firstBatchMilliseconds == nil {
                        firstBatchMilliseconds = milliseconds(from: startedAt, to: clock.now)
                    }
                case .coreFinished:
                    coreCompleteMilliseconds = milliseconds(from: startedAt, to: clock.now)
                case let .metadataPatches(patches):
                    workCounts.metadataPatches += patches.count
                }
            }

            guard let firstBatchMilliseconds, let coreCompleteMilliseconds else {
                throw BenchmarkError.missingCoreEvents
            }
            guard workCounts.coreEntries == 1000,
                  priority.probes.isEmpty ? workCounts.metadataPatches == 0 : true
            else {
                throw BenchmarkError.invalidWorkCounts(workCounts)
            }
            return Sample(
                firstBatchMilliseconds: firstBatchMilliseconds,
                coreCompleteMilliseconds: coreCompleteMilliseconds,
                workCounts: workCounts,
            )
        }
    }

    private static func milliseconds(
        from start: ContinuousClock.Instant,
        to end: ContinuousClock.Instant,
    ) -> Double {
        let components = start.duration(to: end).components
        return Double(components.seconds) * 1000 + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}

private extension Range where Bound == Int {
    func asyncMap<Element>(_ transform: @escaping (Int) async throws -> Element) async throws -> [Element] {
        var results: [Element] = []
        for value in self {
            try await results.append(transform(value))
        }
        return results
    }
}

private extension EntryLoadingBenchmark {
    struct Fixture {
        let directory: URL

        static func make(entryCount: Int) throws -> Fixture {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("voyager-entry-loading-benchmark-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for index in 0 ..< entryCount {
                let file = directory.appendingPathComponent("entry-\(index).txt")
                guard FileManager.default.createFile(atPath: file.path, contents: Data()) else {
                    throw BenchmarkError.fixtureCreationFailed
                }
            }
            return Fixture(directory: directory)
        }

        func remove() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    struct Sample {
        let firstBatchMilliseconds: Double
        let coreCompleteMilliseconds: Double
        let workCounts: WorkCounts
    }

    struct WorkCounts: Codable, Equatable {
        var coreEntries = 0
        var metadataPatches = 0
        var folderCountProbes = 0
    }

    struct Percentiles: Codable {
        let p50: Double
        let p95: Double

        init(_ values: [Double]) {
            let sorted = values.sorted()
            p50 = sorted[(sorted.count - 1) / 2]
            p95 = sorted[Int((Double(sorted.count) * 0.95).rounded(.up)) - 1]
        }
    }

    struct InformationalPriorityMilliseconds: Codable {
        let spotlight: [Double]
        let tags: [Double]
    }

    struct Report: Codable {
        let sampleCount: Int
        let firstBatchMilliseconds: Percentiles
        let coreCompleteMilliseconds: Percentiles
        let workCounts: [WorkCounts]
        let informationalPriorityMilliseconds: InformationalPriorityMilliseconds
    }

    enum BenchmarkError: Error {
        case fixtureCreationFailed
        case missingCoreEvents
        case invalidWorkCounts(WorkCounts)
    }
}
