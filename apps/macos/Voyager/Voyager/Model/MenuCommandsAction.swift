import ComposableArchitecture
import VoyagerFeaturesUpdateVersion

enum MenuCommandsAction: ViewAction {
    case view(View)
    case delegate(Delegate)

    enum View {
        case app(MenuCommandItem.AppCommand)
        case viewCommand(MenuCommandItem.ViewCommand)
        case edit(MenuCommandItem.EditCommand)
    }

    enum Delegate {
        case windowManager(WindowManagerAction)
        case lifecycle(AppLifecycleAction.Delegate)
        case updater(UpdaterAction)
    }
}
