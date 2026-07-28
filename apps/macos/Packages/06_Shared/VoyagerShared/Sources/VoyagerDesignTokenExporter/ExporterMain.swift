import Foundation

@main
enum VoyagerDesignTokenExporter {
    private static let usage = """
    Usage: VoyagerDesignTokenExporter --css-output <path> --metadata-output <path> [--check]

      --check  생성 파일을 수정하지 않고 현재 SwiftUI 결과와 일치하는지 검사합니다.
    """

    @MainActor
    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            if arguments.contains("--help") {
                print(usage)
                return
            }
            let options = try ExporterOptions(arguments: arguments)
            let snapshot = try SwiftUITokenSnapshot.capture()
            try reconcile(
                content: snapshot.mergingCSS(at: options.cssOutputPath),
                path: options.cssOutputPath,
                checkOnly: options.checkOnly,
            )
            try reconcile(
                content: snapshot.materialMetadataSource,
                path: options.metadataOutputPath,
                checkOnly: options.checkOnly,
            )
            print(options.checkOnly ? "SwiftUI token outputs are current." : "SwiftUI token outputs updated.")
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            Foundation.exit(EXIT_FAILURE)
        }
    }

    private static func reconcile(content: String, path: String, checkOnly: Bool) throws {
        let current = try? String(contentsOfFile: path, encoding: .utf8)
        if checkOnly {
            guard current == content else {
                throw ExporterError.staleOutput(path)
            }
            return
        }
        guard current != content else { return }
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

private struct ExporterOptions {
    let cssOutputPath: String
    let metadataOutputPath: String
    let checkOnly: Bool

    init(arguments: [String]) throws {
        var cssOutputPath: String?
        var metadataOutputPath: String?
        var checkOnly = false
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--css-output":
                index += 1
                guard index < arguments.count else { throw ExporterError.missingValue("--css-output") }
                cssOutputPath = arguments[index]
            case "--metadata-output":
                index += 1
                guard index < arguments.count else { throw ExporterError.missingValue("--metadata-output") }
                metadataOutputPath = arguments[index]
            case "--check":
                checkOnly = true
            case let argument:
                throw ExporterError.unknownArgument(argument)
            }
            index += 1
        }

        guard let cssOutputPath else { throw ExporterError.missingArgument("--css-output") }
        guard let metadataOutputPath else { throw ExporterError.missingArgument("--metadata-output") }
        self.cssOutputPath = cssOutputPath
        self.metadataOutputPath = metadataOutputPath
        self.checkOnly = checkOnly
    }
}

private enum ExporterError: Error, CustomStringConvertible {
    case missingArgument(String)
    case missingValue(String)
    case staleOutput(String)
    case unknownArgument(String)

    var description: String {
        switch self {
        case let .missingArgument(argument):
            "Missing required argument: \(argument)"
        case let .missingValue(argument):
            "Missing value for argument: \(argument)"
        case let .staleOutput(path):
            "Generated output is stale: \(path). Run `mise run swiftui-tokens`."
        case let .unknownArgument(argument):
            "Unknown argument: \(argument)"
        }
    }
}
