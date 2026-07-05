import SwiftUI

/// Standalone SoloChef demo — no glasses connection required.
struct SoloChefDemoView: View {
    @State private var model = AppViewModel.demoMode()

    var body: some View {
        HomeView(model: model, cameraConnected: true, glasses: nil)
    }
}

#Preview {
    NavigationStack {
        SoloChefDemoView()
    }
}
