import ComposableArchitecture
import Foundation
import VoyagerPagesFileManager

@ObservableState
struct WindowSessionState: Equatable, Identifiable {
    var id: UUID
    var window: FileManagerWindowFeature.State
}
