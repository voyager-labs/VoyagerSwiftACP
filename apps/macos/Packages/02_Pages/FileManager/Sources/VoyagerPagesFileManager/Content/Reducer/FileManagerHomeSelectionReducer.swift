import ComposableArchitecture
import Foundation
import VoyagerFeaturesContentPageNavigation
import VoyagerShared

@Reducer
struct FileManagerHomeSelectionReducer {
    typealias State = FileManagerContentState
    typealias Action = FileManagerContentAction

    @Dependency(\.fileManagerClient)
    private var fileManagerClient
    @Dependency(\.homePickerClient)
    private var homePickerClient
    @Dependency(\.homeAiChatClient)
    private var homeAiChatClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .view(.homeAppeared):
                return loadHomeDirectoryItemCounts()

            case let .internal(.homeDirectoryItemCountsLoaded(counts)):
                state.homeDirectoryItemCounts = counts
                return .none

            // MARK: - Fixed Directory: resolve → delegate

            case let .view(.homeSelectionTapped(.fixedDirectory(directory))):
                let anchor = FileManagerHomeDirectoryResolver.resolve(directory, using: fileManagerClient)
                return .send(.delegate(.homePageAnchorSelected(anchor)))

            // MARK: - Open Directory Picker → internal

            case .view(.homeSelectionTapped(.openDirectory)):
                return .run { send in
                    let result = await homePickerClient.pickDirectory()
                    await send(.internal(.homeDirectoryPickerFinished(result)))
                }

            // MARK: - Open Collection Picker → internal

            case .view(.homeSelectionTapped(.openCollection)):
                return .run { send in
                    let result = await homePickerClient.pickCollectionFile()
                    await send(.internal(.homeCollectionPickerFinished(result)))
                }

            // MARK: - Start AI Chat → internal

            case .view(.homeSelectionTapped(.startAiChat)):
                return .run { send in
                    let result = await homeAiChatClient.createSession()
                    await send(.internal(.homeAiChatSessionCreated(result)))
                }

            // MARK: - Directory Picker Result

            case let .internal(.homeDirectoryPickerFinished(.selected(path))):
                return .send(.delegate(.homePageAnchorSelected(.directory(path: path))))

            case .internal(.homeDirectoryPickerFinished(.cancelled)),
                 .internal(.homeDirectoryPickerFinished(.failed)):
                return .none

            // MARK: - Collection Picker Result

            case let .internal(.homeCollectionPickerFinished(.selected(url))):
                return .send(.delegate(.homePageAnchorSelected(.collectionFile(url: url))))

            case .internal(.homeCollectionPickerFinished(.cancelled)),
                 .internal(.homeCollectionPickerFinished(.failed)):
                return .none

            // MARK: - AI Chat Session Result

            case let .internal(.homeAiChatSessionCreated(.selected(sessionID))):
                return .send(.delegate(.homePageAnchorSelected(.aiChat(sessionID: sessionID))))

            case .internal(.homeAiChatSessionCreated(.cancelled)),
                 .internal(.homeAiChatSessionCreated(.failed)):
                return .none

            default:
                return .none
            }
        }
    }

    private func loadHomeDirectoryItemCounts() -> Effect<Action> {
        .run { send in
            var counts: [FileManagerHomeDirectory: Int] = [:]
            for directory in FileManagerHomeDirectory.allCases {
                guard let url = FileManagerHomeDirectoryResolver.url(for: directory, using: fileManagerClient) else {
                    continue
                }
                counts[directory] = try? fileManagerClient
                    .contentsOfDirectory(url, nil, [.skipsHiddenFiles])
                    .count
            }
            await send(.internal(.homeDirectoryItemCountsLoaded(counts)))
        }
    }
}
