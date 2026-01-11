import ComposableArchitecture
import SwiftUI

struct CompleteStepView: View {
    let store: StoreOf<CompleteFeature>
    var isCentered: Bool = false

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            VStack(alignment: isCentered ? .center : .leading, spacing: 12) {
                Text("Setup is finished and Voyager is ready to use.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(isCentered ? .center : .leading)
                Text("Click Start using Voyager to open your first file manager window.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(isCentered ? .center : .leading)

                if viewStore.isOpeningWindow {
                    ProgressView()
                        .controlSize(.small)
                }

                if let error = viewStore.openWindowError {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                    Button("Retry") {
                        viewStore.send(.retryTapped)
                    }
                } else {
                    Text("If it fails, you'll see Retry to try again.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(isCentered ? .center : .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: isCentered ? .center : .leading)
        }
    }
}
