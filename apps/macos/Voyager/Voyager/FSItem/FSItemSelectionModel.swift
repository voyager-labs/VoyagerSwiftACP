import Foundation

@MainActor
final class FSItemSelectionModel: ObservableObject {
    @Published var rootURL: URL
    @Published var selectedItem: FSItemFeature.State?

    init(rootURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")) {
        self.rootURL = rootURL
    }
}
