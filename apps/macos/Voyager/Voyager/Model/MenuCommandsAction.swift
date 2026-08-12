import ComposableArchitecture
import VoyagerFeaturesUpdateVersion

@CasePathable
enum MenuCommandsAction: ViewAction, CasePathable {
    case view(View)
    case delegate(Delegate)

    @CasePathable
    enum View {
        case app(MenuCommandItem.AppCommand)
        case viewCommand(MenuCommandItem.ViewCommand)
        case edit(MenuCommandItem.EditCommand)
    }

    @CasePathable
    enum Delegate {
        case windowManager(WindowManagerAction)
        case updater(UpdaterAction)
    }
}
