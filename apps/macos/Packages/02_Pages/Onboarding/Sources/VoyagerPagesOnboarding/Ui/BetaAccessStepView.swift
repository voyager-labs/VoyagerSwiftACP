import ComposableArchitecture
import SwiftUI
import VoyagerFeaturesLicenseAuth

// Legacy LicenseAuthStepView — Task 8 에서 삭제 예정
// UnlockLicenseAuthStepView 로 교체됨
struct LicenseAuthStepView: View {
    let store: StoreOf<UnlockLicenseAuthFeature>

    var body: some View {
        UnlockLicenseAuthStepView(store: store)
    }
}
