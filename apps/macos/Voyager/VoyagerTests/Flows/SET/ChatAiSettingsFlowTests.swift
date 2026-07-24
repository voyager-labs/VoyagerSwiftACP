// FLOW-ID: set.chat_ai_settings
import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerEntitiesAppPreferences
import VoyagerFeaturesAiChat
@testable import VoyagerPagesFileManager
@testable import VoyagerPagesSettings
import VoyagerShared
import XCTest

@MainActor
final class ChatAiSettingsFlowTests: XCTestCase {
    // FLOW-PATH: persisted_default_to_new_chat

    /// set.chat_ai_settings: persisted_default_to_new_chat
    /// Settings에서 저장한 Chat 기본값이 실제 저장 client를 거쳐 다음 New Chat 선택으로 전달되는지 검증한다.
    /// - 검증 내용: Settings autosave Data, live client reload, FileManager New Chat seed
    /// - 사전 조건: OpenAI가 연결되어 있고 GPT-5 모델이 Chat catalog에 존재한다.
    /// - 기대 결과: OpenAI/GPT-5/high 기본값이 저장되고 다음 New Chat에 같은 선택이 적용된다.
    func testSettingsPersistedDefaultSeedsNextFileManagerNewChat() async {
        let userDefaultsClient = UserDefaultsClient.testValue
        userDefaultsClient.setObject(nil, SettingsKeys.aiChatDefaultSettings)
        let chatDefaultsClient = AiChatDefaultSettingsClient.live(userDefaultsClient: userDefaultsClient)
        let model = Self.openAIModel
        let providerSelection = PersistedAIProviderSelection(rawValue: AiProvider.openai.rawValue)
        let modelSelection = PersistedAIModelSelection(
            providerRawValue: AiProvider.openai.rawValue,
            modelRawValue: model.rawModelID,
        )
        let expectedSettings = AiChatDefaultSettings(
            provider: providerSelection,
            model: modelSelection,
            thinking: .effort(AiThinkingEffort.high.rawValue),
        )
        let settingsStore = TestStore(initialState: AiSettingsState(
            chatModelsByProvider: [.openai: [model]],
            chatModelCatalogPhase: .loaded,
        )) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiChatDefaultSettingsClient = chatDefaultsClient
        }
        // store.exhaustivity = .off: Settings production autosave와 FileManager handoff의 최종 저장값만 검증한다.
        settingsStore.exhaustivity = .off

        await settingsStore.send(.chatProviderChanged(providerSelection))
        await settingsStore.finish()
        await settingsStore.send(.chatModelChanged(modelSelection))
        await settingsStore.finish()
        await settingsStore.send(.chatThinkingChanged(.effort(.high)))
        await settingsStore.finish()

        XCTAssertNotNil(userDefaultsClient.object(SettingsKeys.aiChatDefaultSettings) as? Data)
        XCTAssertEqual(chatDefaultsClient.load(), expectedSettings)

        var fileManagerState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        fileManagerState.inspector.inspectorVisible = true
        fileManagerState.inspector.activeMode = .chat
        fileManagerState.inspector.aiChat = AiChatFeature.State(
            mode: .sessions,
            modelListState: .loaded([model]),
        )
        let fileManagerStore = TestStore(initialState: fileManagerState) {
            FileManagerFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.aiChatDefaultSettingsClient = chatDefaultsClient
        }
        // store.exhaustivity = .off: FileManager에서 persisted default를 읽어 New Chat seed로 넘기는 production handoff만 검증한다.
        fileManagerStore.exhaustivity = .off

        await fileManagerStore.send(.request(.newChat))
        await fileManagerStore.receive { action in
            guard case let .inspector(.aiChat(.prepareTransientNewChatWithContext(_, seed))) = action else {
                return false
            }
            return seed == AiChatNewChatSelectionSeed(
                modelHandle: model.id,
                selectedThinking: .effort(.high),
            )
        }

        XCTAssertEqual(fileManagerStore.state.inspector.aiChat.selectedModelHandle, model.id)
        XCTAssertEqual(fileManagerStore.state.inspector.aiChat.selectedThinking, .effort(.high))
    }
}

private extension ChatAiSettingsFlowTests {
    static let openAIModel = AiProviderModel(
        id: .init(provider: .openai, rawValue: "gpt-5"),
        provider: .openai,
        rawModelID: "gpt-5",
        displayName: "GPT-5",
        providerDisplayName: "OpenAI",
        thinkingCapability: .effort(values: [.low, .medium, .high], defaultValue: .medium),
        supportsThinkingNone: true,
    )
}
