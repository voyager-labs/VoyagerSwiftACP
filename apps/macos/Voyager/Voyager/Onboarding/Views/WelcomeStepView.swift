import ComposableArchitecture
import SwiftUI

struct WelcomeStepView: View {
    let store: StoreOf<WelcomeFeature>
    var isCentered: Bool = false

    var body: some View {
        WithViewStore(store, observe: { $0 }) { _ in
            VStack(alignment: isCentered ? .center : .leading, spacing: 12) {
                Text("Voyager runs a four-step setup. You can move forward only after each step is complete.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(isCentered ? .center : .leading)
                Text("Your files stay on your Mac; nothing is uploaded during onboarding.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(isCentered ? .center : .leading)
                Text("If you quit and reopen Voyager, it resumes at the last saved step.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(isCentered ? .center : .leading)
            }
            .frame(maxWidth: .infinity, alignment: isCentered ? .center : .leading)
        }
    }
}
