import Foundation
@testable import VoyagerEntitiesEntry
import XCTest

private actor DiscoveryGate {
    private var waiters: [String: CheckedContinuation<Void, Never>] = [:]
    private var started: Set<String> = []

    func wait(_ key: String) async {
        started.insert(key)
        await withCheckedContinuation { waiters[key] = $0 }
    }

    func resume(_ key: String) {
        waiters.removeValue(forKey: key)?.resume()
    }

    func isStarted(_ key: String) -> Bool {
        started.contains(key)
    }
}

private actor CallCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }

    func count() -> Int {
        value
    }
}

final class EOP007EntryContextActionsTests: XCTestCase {
    /// EOP-007-open_with_cache: 무효화 중인 동일 타입 조회는 이전 in-flight 결과를 재사용하지 않는다.
    /// - 검증 내용: 첫 조회를 gate에 묶은 뒤 무효화하고, 새 조회가 fresh underlying load를 수행하며 fresh 결과를 cache에 남기는지 확인한다.
    /// - 사전 조건: 동일 UTType cache, 이전 결과와 새 결과를 반환하는 두 번의 gated load가 있다.
    /// - 기대 결과: underlying load 2회, post-invalidation 조회는 새 결과, 이후 cache 조회도 새 결과다.
    func testApplicationDiscoveryCacheInvalidationDuringInFlightLoadStartsFreshGeneration() async {
        let cache = ApplicationDiscoveryCache()
        let gate = DiscoveryGate()
        let calls = CallCounter()
        let stale = ApplicationInfo(id: "stale", name: "Stale", bundleID: "stale")
        let fresh = ApplicationInfo(id: "fresh", name: "Fresh", bundleID: "fresh")

        let first = Task {
            await cache.applications(for: "public.plain-text") {
                await calls.increment()
                await gate.wait("first")
                return [stale]
            }
        }
        while await !gate.isStarted("first") {
            await Task.yield()
        }

        await cache.invalidate("public.plain-text")
        let second = Task {
            await cache.applications(for: "public.plain-text") {
                await calls.increment()
                await gate.wait("second")
                return [fresh]
            }
        }
        while await !gate.isStarted("second") {
            await Task.yield()
        }

        await gate.resume("first")
        await gate.resume("second")
        let firstResult = await first.value
        let secondResult = await second.value
        let cachedResult = await cache.applications(for: "public.plain-text") { XCTFail("cache miss")
            return []
        }

        let callCount = await calls.count()
        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(firstResult, [stale])
        XCTAssertEqual(secondResult, [fresh])
        XCTAssertEqual(cachedResult, [fresh])
    }

    /// EOP-007-reveal_entries_in_finder: Finder reveal은 global NSFileViewer 설정과 무관하게 Finder를 대상으로 한다.
    /// - 검증 내용: 생성된 AppleScript가 Finder bundle ID와 reveal 명령을 명시하는지 확인한다.
    /// - 사전 조건: 일반 파일 URL 하나가 있다.
    /// - 기대 결과: script가 default viewer가 아닌 `com.apple.finder`를 직접 대상으로 한다.
    func testFinderRevealTargetsFinderBundleDirectly() {
        let source = EntryFinderReveal.scriptSource(for: [URL(fileURLWithPath: "/tmp/report.txt")])

        XCTAssertTrue(source.contains("tell application id \"com.apple.finder\""))
        XCTAssertTrue(source.contains("activate"))
        XCTAssertTrue(source.contains("reveal POSIX file \"/tmp/report.txt\""))
    }

    /// EOP-007-reveal_entries_in_finder: Finder reveal script는 파일 경로의 backslash와 따옴표를 escape한다.
    /// - 검증 내용: 특수문자 파일명이 AppleScript 문자열을 깨뜨리지 않는지 확인한다.
    /// - 사전 조건: backslash와 따옴표가 포함된 파일 URL이 있다.
    /// - 기대 결과: 생성된 script가 escape된 POSIX file literal을 포함한다.
    func testFinderRevealEscapesAppleScriptPathLiteral() {
        let source = EntryFinderReveal.scriptSource(for: [
            URL(fileURLWithPath: "/tmp/quote\"\\report.txt"),
        ])

        XCTAssertTrue(source.contains(#"reveal POSIX file "/tmp/quote\"\\report.txt"#))
    }
}
