import Foundation
import VoyagerExternalAgentRuntime

struct CodexExecLiveComposition {
    let controller: CodexExecProcessController
    let runtimeAdapter: CodexExecRuntimeAdapter
    let executableURL: URL?
    let codexHome: URL
    let readinessProbe: CodexExecReadinessProbe
    let legacySessionPreparer: CodexLegacySessionPreparer

    var controllerIdentity: ObjectIdentifier {
        controller.identity
    }

    init(
        controller: CodexExecProcessController = CodexExecProcessController(),
        executableURL: URL? = nil,
        codexHome: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex"),
        readinessProbe: CodexExecReadinessProbe = CodexExecReadinessProbe(),
        legacySessionPreparer: CodexLegacySessionPreparer = CodexLegacySessionPreparer(),
    ) {
        self.controller = controller
        self.executableURL = executableURL
        self.codexHome = codexHome
        self.readinessProbe = readinessProbe
        self.legacySessionPreparer = legacySessionPreparer
        runtimeAdapter = CodexExecRuntimeAdapter(
            controller: controller,
            readinessProbe: readinessProbe,
            executableURL: executableURL,
            codexHome: codexHome,
            legacySessionPreparer: legacySessionPreparer,
        )
    }

    static let live = CodexExecLiveComposition()
}
