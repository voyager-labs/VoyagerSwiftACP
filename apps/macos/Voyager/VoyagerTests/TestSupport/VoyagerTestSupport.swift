import Foundation

enum VoyagerTestSupport {
    static func hostApplicationBundle() -> Bundle {
        let testBundle = Bundle(for: VoyagerTestsBundleAnchor.self)
        let roots = [Bundle.main.bundleURL, testBundle.bundleURL]
        let candidateBundles = roots
            .flatMap(candidateBundles(near:))
            .reduce(into: (bundles: [Bundle](), urls: Set<URL>())) { result, bundle in
                let url = bundle.bundleURL.standardized
                guard result.urls.insert(url).inserted else { return }
                result.bundles.append(bundle)
            }

        if let bundle = candidateBundles.bundles.first(where: hasRegistryResource) {
            return bundle
        }

        let searchedPaths = candidateBundles.bundles
            .map(\.bundleURL.path)
            .sorted()
            .joined(separator: ", ")
        preconditionFailure(
            "ProductAnalyticsRegistry.json was not found in a host application bundle. Searched: \(searchedPaths)",
        )
    }

    private static func candidateBundles(near root: URL) -> [Bundle] {
        var bundles = Bundle(path: root.path).map { [$0] } ?? []
        var directories: Set<URL> = []
        var current = root

        while current.path != "/" {
            if current.pathExtension == "app", let bundle = Bundle(path: current.path) {
                bundles.append(bundle)
            }
            directories.insert(current.deletingLastPathComponent().standardized)
            current.deleteLastPathComponent()
        }

        for directory in directories {
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles],
            ) else {
                continue
            }
            bundles.append(contentsOf: children
                .filter { $0.pathExtension == "app" }
                .compactMap { Bundle(path: $0.path) })
        }

        return bundles
    }

    private static func hasRegistryResource(in bundle: Bundle) -> Bool {
        bundle.url(forResource: "ProductAnalyticsRegistry", withExtension: "json") != nil
    }
}

private final class VoyagerTestsBundleAnchor: NSObject {}
