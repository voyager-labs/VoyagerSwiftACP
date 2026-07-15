import ComposableArchitecture
import VoyagerPagesFileManager

@CasePathable
enum WindowSessionAction {
    case window(FileManagerWindowFeature.Action)
}
