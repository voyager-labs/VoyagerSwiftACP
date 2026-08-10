import AppKit
import Foundation
import Highlighter

struct AiChatSyntaxHighlightingClient {
    static let maximumCacheEntries = 128
    static let maximumCacheBytes = 8 * 1024 * 1024
    static let maximumSourceBytes = 64 * 1024
    static let maximumLineCount = 2000

    private let highlightOperation: @Sendable (Request) async -> Result
    private let cacheMetricsOperation: @Sendable () async -> CacheMetrics

    func highlight(_ request: Request) async -> Result {
        await highlightOperation(request)
    }

    func cacheMetrics() async -> CacheMetrics {
        await cacheMetricsOperation()
    }

    static func live() -> Self {
        let engine = AiChatHighlighterEngine()
        let coordinator = AiChatSyntaxHighlightingCoordinator(
            coalescingDelay: .milliseconds(80),
            supportedLanguages: { try await engine.supportedLanguages() },
            highlight: { code, language, theme in
                try await engine.highlight(code: code, language: language, theme: theme)
            },
        )
        return Self(
            highlightOperation: { request in await coordinator.highlight(request) },
            cacheMetricsOperation: { await coordinator.cacheMetrics() },
        )
    }

    static func testing(
        coalescingDelay: Duration,
        supportedLanguages: @escaping @Sendable () async throws -> Set<String>,
        highlight: @escaping @Sendable (String, String, String) async throws -> [Run],
    ) -> Self {
        let coordinator = AiChatSyntaxHighlightingCoordinator(
            coalescingDelay: coalescingDelay,
            supportedLanguages: supportedLanguages,
            highlight: highlight,
        )
        return Self(
            highlightOperation: { request in await coordinator.highlight(request) },
            cacheMetricsOperation: { await coordinator.cacheMetrics() },
        )
    }

    struct RequestIdentity: Equatable, Hashable {
        let rawValue: String
    }

    struct Request: Equatable {
        let identity: RequestIdentity
        let code: String
        let languageLabel: String?
        let appearance: Appearance
        let typographyVersion: Int
        let generation: UInt64
    }

    struct Result: Equatable {
        let source: String
        let originalLanguage: String?
        let normalizedLanguage: String?
        let theme: String
        let typographyVersion: Int
        let generation: UInt64
        let runs: [Run]
        let disposition: Disposition
        let isEligibleForDisplay: Bool
    }

    struct Run: Equatable {
        let sourceRange: SourceRange
        let attributes: HighlightAttributes

        static func plain(_ source: String) -> Self {
            Self(
                sourceRange: .init(utf16Offsets: 0 ..< source.utf16.count),
                attributes: .init(),
            )
        }
    }

    struct SourceRange: Equatable, Hashable {
        let utf16Offsets: Range<Int>
    }

    struct HighlightAttributes: Equatable {
        let foreground: ColorComponents?
        let background: ColorComponents?
        let isBold: Bool
        let isItalic: Bool

        var isPlain: Bool {
            foreground == nil && background == nil && !isBold && !isItalic
        }

        init(
            foreground: ColorComponents? = nil,
            background: ColorComponents? = nil,
            isBold: Bool = false,
            isItalic: Bool = false,
        ) {
            self.foreground = foreground
            self.background = background
            self.isBold = isBold
            self.isItalic = isItalic
        }
    }

    struct ColorComponents: Equatable {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
    }

    struct CacheMetrics: Equatable {
        let entryCount: Int
        let estimatedBytes: Int
    }

    enum Appearance: Equatable, Hashable {
        case light, dark

        var theme: String {
            switch self {
            case .light:
                "default-light"
            case .dark:
                "default-dark"
            }
        }
    }

    enum Disposition: Equatable {
        case highlighted
        case plain(FallbackReason)
        case stale
    }

    enum FallbackReason: Equatable {
        case missingLanguage
        case unsupportedLanguage
        case preflightLimit
        case cancelled
        case initializationFailure
        case themeFailure
        case highlightFailure
    }

    enum EngineFailure: Error, Equatable {
        case initialization
        case theme
        case highlight
    }
}

private actor AiChatHighlighterEngine {
    private var highlighter: Highlighter?
    private var didAttemptInitialization = false

    func supportedLanguages() throws -> Set<String> {
        let highlighter = try initializedHighlighter()
        return Set(highlighter.supportedLanguages().map { $0.lowercased() })
    }

    func highlight(
        code: String,
        language: String,
        theme: String,
    ) throws -> [AiChatSyntaxHighlightingClient.Run] {
        let highlighter = try initializedHighlighter()
        guard highlighter.setTheme(theme) else {
            throw AiChatSyntaxHighlightingClient.EngineFailure.theme
        }
        guard let attributed = highlighter.highlight(code, as: language),
              attributed.string == code
        else {
            throw AiChatSyntaxHighlightingClient.EngineFailure.highlight
        }
        return Self.runs(from: attributed)
    }

    private func initializedHighlighter() throws -> Highlighter {
        if didAttemptInitialization {
            guard let highlighter else {
                throw AiChatSyntaxHighlightingClient.EngineFailure.initialization
            }
            return highlighter
        }

        didAttemptInitialization = true
        guard let highlighter = Highlighter() else {
            throw AiChatSyntaxHighlightingClient.EngineFailure.initialization
        }
        let availableThemes = Set(highlighter.availableThemes())
        guard availableThemes.contains("default-light"),
              availableThemes.contains("default-dark"),
              highlighter.setTheme("default-light"),
              highlighter.setTheme("default-dark"),
              highlighter.setTheme("default-light")
        else {
            throw AiChatSyntaxHighlightingClient.EngineFailure.initialization
        }
        self.highlighter = highlighter
        return highlighter
    }

    private static func runs(from attributed: NSAttributedString) -> [AiChatSyntaxHighlightingClient.Run] {
        var runs: [AiChatSyntaxHighlightingClient.Run] = []
        let fullRange = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttributes(in: fullRange) { attributes, range, _ in
            let font = attributes[.font] as? NSFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            runs.append(.init(
                sourceRange: .init(utf16Offsets: range.location ..< NSMaxRange(range)),
                attributes: .init(
                    foreground: colorComponents(attributes[.foregroundColor] as? NSColor),
                    background: colorComponents(attributes[.backgroundColor] as? NSColor),
                    isBold: traits.contains(.bold),
                    isItalic: traits.contains(.italic),
                ),
            ))
        }
        return runs.isEmpty ? [.plain(attributed.string)] : runs
    }

    private static func colorComponents(
        _ color: NSColor?,
    ) -> AiChatSyntaxHighlightingClient.ColorComponents? {
        guard let color = color?.usingColorSpace(.sRGB) else {
            return nil
        }
        return .init(
            red: Double(color.redComponent),
            green: Double(color.greenComponent),
            blue: Double(color.blueComponent),
            alpha: Double(color.alphaComponent),
        )
    }
}

private actor AiChatSyntaxHighlightingCoordinator {
    typealias Client = AiChatSyntaxHighlightingClient

    private let coalescingDelay: Duration
    private let supportedLanguagesOperation: @Sendable () async throws -> Set<String>
    private let engineHighlightOperation: @Sendable (String, String, String) async throws -> [Client.Run]
    private var supportedLanguages: Set<String>?
    private var cache: [CacheKey: CacheEntry] = [:]
    private var lru: [CacheKey] = []
    private var estimatedCacheBytes = 0
    private var nextRequestID: UInt64 = 0
    private var freshnessByIdentity: [Client.RequestIdentity: (highestGeneration: UInt64, latestRequestID: UInt64)] =
        [:]

    init(
        coalescingDelay: Duration,
        supportedLanguages: @escaping @Sendable () async throws -> Set<String>,
        highlight: @escaping @Sendable (String, String, String) async throws -> [Client.Run],
    ) {
        self.coalescingDelay = coalescingDelay
        supportedLanguagesOperation = supportedLanguages
        engineHighlightOperation = highlight
    }

    func cacheMetrics() -> Client.CacheMetrics {
        .init(entryCount: cache.count, estimatedBytes: estimatedCacheBytes)
    }

    func highlight(_ request: Client.Request) async -> Client.Result {
        guard let context = beginRequest(request) else {
            return staleResult(
                request,
                normalizedLanguage: Self.normalizedLanguage(request.languageLabel),
                theme: request.appearance.theme,
            )
        }
        if let result = preflightResult(for: request, context: context) {
            return result
        }
        if let result = missingLanguageResult(for: request, context: context) {
            return result
        }
        if let result = await trailingEdgeResult(for: request, context: context) {
            return result
        }

        switch await prepareLanguage(for: request, context: context) {
        case let .result(result):
            return result
        case let .highlight(key):
            return await highlightSupportedLanguage(request, context: context, key: key)
        }
    }

    private func beginRequest(_ request: Client.Request) -> RequestContext? {
        if let freshness = freshnessByIdentity[request.identity],
           request.generation < freshness.highestGeneration
        {
            return nil
        }

        nextRequestID &+= 1
        let requestID = nextRequestID
        let highestGeneration = max(
            freshnessByIdentity[request.identity]?.highestGeneration ?? request.generation,
            request.generation,
        )
        freshnessByIdentity[request.identity] = (
            highestGeneration: highestGeneration,
            latestRequestID: requestID,
        )
        return .init(
            identity: request.identity,
            requestID: requestID,
            generation: request.generation,
            theme: request.appearance.theme,
            normalizedLanguage: Self.normalizedLanguage(request.languageLabel),
        )
    }

    private func preflightResult(
        for request: Client.Request,
        context: RequestContext,
    ) -> Client.Result? {
        guard request.code.utf8.count > Client.maximumSourceBytes
            || Self.lineCount(request.code) > Client.maximumLineCount
        else {
            return nil
        }
        return plainResult(
            request,
            normalizedLanguage: context.normalizedLanguage,
            theme: context.theme,
            reason: .preflightLimit,
            isEligibleForDisplay: true,
        )
    }

    private func missingLanguageResult(
        for request: Client.Request,
        context: RequestContext,
    ) -> Client.Result? {
        guard context.normalizedLanguage == nil else {
            return nil
        }
        let key = CacheKey(
            code: request.code,
            languageMode: .missing,
            appearance: request.appearance,
            theme: context.theme,
            typographyVersion: request.typographyVersion,
        )
        if let cached = cachedResult(
            for: key,
            request: request,
            originalLanguage: request.languageLabel,
            normalizedLanguage: nil,
        ) {
            return cached
        }
        let result = plainResult(
            request,
            normalizedLanguage: nil,
            theme: context.theme,
            reason: .missingLanguage,
            isEligibleForDisplay: true,
        )
        insert(result, for: key)
        return result
    }

    private func trailingEdgeResult(
        for request: Client.Request,
        context: RequestContext,
    ) async -> Client.Result? {
        do {
            if coalescingDelay != .zero {
                try await Task.sleep(for: coalescingDelay)
            }
        } catch {
            guard isCurrent(context) else {
                return staleResult(
                    request,
                    normalizedLanguage: context.normalizedLanguage,
                    theme: context.theme,
                )
            }
            return plainResult(
                request,
                normalizedLanguage: context.normalizedLanguage,
                theme: context.theme,
                reason: .cancelled,
                isEligibleForDisplay: false,
            )
        }
        guard isCurrent(context) else {
            return staleResult(
                request,
                normalizedLanguage: context.normalizedLanguage,
                theme: context.theme,
            )
        }
        return nil
    }

    private func prepareLanguage(
        for request: Client.Request,
        context: RequestContext,
    ) async -> LanguagePreparation {
        guard let normalizedLanguage = context.normalizedLanguage else {
            return .result(plainResult(
                request,
                normalizedLanguage: nil,
                theme: context.theme,
                reason: .missingLanguage,
                isEligibleForDisplay: true,
            ))
        }

        let languages: Set<String>
        do {
            languages = try await loadSupportedLanguages()
        } catch {
            return languageLoadFailure(
                error,
                request: request,
                normalizedLanguage: normalizedLanguage,
                context: context,
            )
        }
        guard isCurrent(context) else {
            return .result(staleResult(
                request,
                normalizedLanguage: normalizedLanguage,
                theme: context.theme,
            ))
        }
        guard !Task.isCancelled else {
            return .result(plainResult(
                request,
                normalizedLanguage: normalizedLanguage,
                theme: context.theme,
                reason: .cancelled,
                isEligibleForDisplay: false,
            ))
        }
        return preparedLanguage(
            normalizedLanguage,
            supportedLanguages: languages,
            request: request,
            context: context,
        )
    }

    private func languageLoadFailure(
        _ error: any Error,
        request: Client.Request,
        normalizedLanguage: String,
        context: RequestContext,
    ) -> LanguagePreparation {
        guard isCurrent(context) else {
            return .result(staleResult(
                request,
                normalizedLanguage: normalizedLanguage,
                theme: context.theme,
            ))
        }
        let isCancellation = Task.isCancelled || error is CancellationError
        return .result(plainResult(
            request,
            normalizedLanguage: normalizedLanguage,
            theme: context.theme,
            reason: isCancellation ? .cancelled : .initializationFailure,
            isEligibleForDisplay: !isCancellation,
        ))
    }

    private func loadSupportedLanguages() async throws -> Set<String> {
        if let supportedLanguages {
            return supportedLanguages
        }
        let loadedLanguages = try await supportedLanguagesOperation()
        supportedLanguages = loadedLanguages
        return loadedLanguages
    }

    private func preparedLanguage(
        _ normalizedLanguage: String,
        supportedLanguages: Set<String>,
        request: Client.Request,
        context: RequestContext,
    ) -> LanguagePreparation {
        let isSupported = supportedLanguages.contains(normalizedLanguage)
        let key = CacheKey(
            code: request.code,
            languageMode: isSupported ? .language(normalizedLanguage) : .unsupported(normalizedLanguage),
            appearance: request.appearance,
            theme: context.theme,
            typographyVersion: request.typographyVersion,
        )
        if let cached = cachedResult(
            for: key,
            request: request,
            originalLanguage: request.languageLabel,
            normalizedLanguage: normalizedLanguage,
        ) {
            return .result(cached)
        }
        guard isSupported else {
            let result = plainResult(
                request,
                normalizedLanguage: normalizedLanguage,
                theme: context.theme,
                reason: .unsupportedLanguage,
                isEligibleForDisplay: true,
            )
            insert(result, for: key)
            return .result(result)
        }
        return .highlight(key)
    }

    private func highlightSupportedLanguage(
        _ request: Client.Request,
        context: RequestContext,
        key: CacheKey,
    ) async -> Client.Result {
        guard let normalizedLanguage = context.normalizedLanguage else {
            return staleResult(request, normalizedLanguage: nil, theme: context.theme)
        }
        do {
            let runs = try await engineHighlightOperation(request.code, normalizedLanguage, context.theme)
            guard isCurrent(context) else {
                return staleResult(request, normalizedLanguage: normalizedLanguage, theme: context.theme)
            }
            if Task.isCancelled {
                return plainResult(
                    request,
                    normalizedLanguage: normalizedLanguage,
                    theme: context.theme,
                    reason: .cancelled,
                    isEligibleForDisplay: false,
                )
            }
            let result = highlightedResult(request, normalizedLanguage: normalizedLanguage, runs: runs)
            insert(result, for: key)
            return result
        } catch {
            guard isCurrent(context) else {
                return staleResult(request, normalizedLanguage: normalizedLanguage, theme: context.theme)
            }
            return engineFailureResult(
                error,
                request: request,
                normalizedLanguage: normalizedLanguage,
                theme: context.theme,
            )
        }
    }

    private func highlightedResult(
        _ request: Client.Request,
        normalizedLanguage: String,
        runs: [Client.Run],
    ) -> Client.Result {
        .init(
            source: request.code,
            originalLanguage: request.languageLabel,
            normalizedLanguage: normalizedLanguage,
            theme: request.appearance.theme,
            typographyVersion: request.typographyVersion,
            generation: request.generation,
            runs: runs,
            disposition: .highlighted,
            isEligibleForDisplay: true,
        )
    }

    private func engineFailureResult(
        _ error: any Error,
        request: Client.Request,
        normalizedLanguage: String,
        theme: String,
    ) -> Client.Result {
        let failureReason: Client.FallbackReason = switch error as? Client.EngineFailure {
        case .some(.initialization): .initializationFailure
        case .some(.theme): .themeFailure
        case .some(.highlight), .none: .highlightFailure
        }
        let isCancellation = Task.isCancelled || error is CancellationError
        return plainResult(
            request,
            normalizedLanguage: normalizedLanguage,
            theme: theme,
            reason: isCancellation ? .cancelled : failureReason,
            isEligibleForDisplay: !isCancellation,
        )
    }

    private func isCurrent(_ context: RequestContext) -> Bool {
        guard let freshness = freshnessByIdentity[context.identity] else {
            return false
        }
        return freshness.highestGeneration == context.generation
            && freshness.latestRequestID == context.requestID
    }
}

private extension AiChatSyntaxHighlightingCoordinator {
    func cachedResult(
        for key: CacheKey,
        request: Client.Request,
        originalLanguage: String?,
        normalizedLanguage: String?,
    ) -> Client.Result? {
        guard let entry = cache[key] else {
            return nil
        }
        touch(key)
        return .init(
            source: request.code,
            originalLanguage: originalLanguage,
            normalizedLanguage: normalizedLanguage,
            theme: key.theme,
            typographyVersion: request.typographyVersion,
            generation: request.generation,
            runs: entry.runs,
            disposition: entry.disposition,
            isEligibleForDisplay: true,
        )
    }

    private func insert(_ result: Client.Result, for key: CacheKey) {
        guard result.isEligibleForDisplay,
              result.disposition != .stale
        else {
            return
        }
        let entry = CacheEntry(
            runs: result.runs,
            disposition: result.disposition,
            estimatedBytes: Self.estimatedBytes(for: key, runs: result.runs),
        )
        guard entry.estimatedBytes <= Client.maximumCacheBytes else {
            return
        }
        if let replaced = cache.updateValue(entry, forKey: key) {
            estimatedCacheBytes -= replaced.estimatedBytes
        }
        estimatedCacheBytes += entry.estimatedBytes
        touch(key)
        while cache.count > Client.maximumCacheEntries || estimatedCacheBytes > Client.maximumCacheBytes {
            guard let oldest = lru.first else {
                break
            }
            lru.removeFirst()
            if let removed = cache.removeValue(forKey: oldest) {
                estimatedCacheBytes -= removed.estimatedBytes
            }
        }
    }

    private func touch(_ key: CacheKey) {
        lru.removeAll { $0 == key }
        lru.append(key)
    }

    private func plainResult(
        _ request: Client.Request,
        normalizedLanguage: String?,
        theme: String,
        reason: Client.FallbackReason,
        isEligibleForDisplay: Bool,
    ) -> Client.Result {
        .init(
            source: request.code,
            originalLanguage: request.languageLabel,
            normalizedLanguage: normalizedLanguage,
            theme: theme,
            typographyVersion: request.typographyVersion,
            generation: request.generation,
            runs: [.plain(request.code)],
            disposition: .plain(reason),
            isEligibleForDisplay: isEligibleForDisplay,
        )
    }

    private func staleResult(
        _ request: Client.Request,
        normalizedLanguage: String?,
        theme: String,
    ) -> Client.Result {
        .init(
            source: request.code,
            originalLanguage: request.languageLabel,
            normalizedLanguage: normalizedLanguage,
            theme: theme,
            typographyVersion: request.typographyVersion,
            generation: request.generation,
            runs: [.plain(request.code)],
            disposition: .stale,
            isEligibleForDisplay: false,
        )
    }

    private static func normalizedLanguage(_ language: String?) -> String? {
        guard let language else {
            return nil
        }
        let normalized = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return nil
        }
        return languageAliases[normalized] ?? normalized
    }

    private static func lineCount(_ source: String) -> Int {
        source.reduce(into: 1) { count, character in
            if character == "\n" {
                count += 1
            }
        }
    }

    private static func estimatedBytes(for key: CacheKey, runs: [Client.Run]) -> Int {
        key.code.utf8.count
            + key.theme.utf8.count
            + key.languageMode.estimatedBytes
            + runs.count * 128
    }

    private static let languageAliases: [String: String] = [
        "c++": "cpp",
        "cs": "csharp",
        "js": "javascript",
        "kt": "kotlin",
        "md": "markdown",
        "objc": "objectivec",
        "py": "python",
        "rb": "ruby",
        "sh": "bash",
        "shell": "bash",
        "ts": "typescript",
        "yml": "yaml",
    ]

    private struct RequestContext {
        let identity: Client.RequestIdentity
        let requestID: UInt64
        let generation: UInt64
        let theme: String
        let normalizedLanguage: String?
    }

    private enum LanguagePreparation {
        case result(Client.Result)
        case highlight(CacheKey)
    }

    struct CacheKey: Equatable, Hashable {
        let code: String
        let languageMode: LanguageMode
        let appearance: Client.Appearance
        let theme: String
        let typographyVersion: Int
    }

    enum LanguageMode: Equatable, Hashable {
        case missing
        case unsupported(String)
        case language(String)

        var estimatedBytes: Int {
            switch self {
            case .missing:
                1
            case let .unsupported(language), let .language(language):
                language.utf8.count + 1
            }
        }
    }

    struct CacheEntry {
        let runs: [Client.Run]
        let disposition: Client.Disposition
        let estimatedBytes: Int
    }
}
