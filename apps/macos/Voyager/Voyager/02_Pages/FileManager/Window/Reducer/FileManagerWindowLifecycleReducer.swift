import ComposableArchitecture
import Foundation

@Reducer
struct FileManagerWindowLifecycleReducer {
    @Dependency(\.userDefaultsClient)
    var userDefaultsClient

    typealias State = FileManagerWindowState
    typealias Action = FileManagerWindowAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                if shouldLogDailyFileManagerOpen(userDefaultsClient) {
                    VoyagerSentryMetricLogger.logMetric(
                        "voyager_file_manager_first_open",
                        value: 1,
                        tags: ["date": currentDateKey()],
                    )
                }

                return .merge(
                    .send(.content(.entryArrangements(.setSortKey(state.content.entryArrangements.sortKey)))),
                    .send(.content(.entryArrangements(.setSortOrder(state.content.entryArrangements.sortOrder)))),
                    .send(.content(.entryArrangements(.setGroupKey(state.content.entryArrangements.groupKey)))),
                    .send(.content(.entries(.loadItems(path: state.content.navigation.currentPath)))),
                    .send(.sidebar(.loadFavorites)),
                    .send(.sidebar(.loadLocations)),
                    .send(.sidebar(.loadTags)),
                )

            case .onDisappear:
                return .none

            default:
                return .none
            }
        }
    }
}

private func shouldLogDailyFileManagerOpen(_ userDefaultsClient: UserDefaultsClient) -> Bool {
    let key = "voyager.file_manager.first_open_date"
    let today = currentDateKey()
    let lastValue = userDefaultsClient.string(key)
    if lastValue == today {
        return false
    }
    userDefaultsClient.setString(today, key)
    return true
}

private func currentDateKey() -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: Date())
}
