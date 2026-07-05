import SwiftUI
import SolosAirGoSDK

/// SoloChef entry point — uses the demo's already-connected glasses (no separate connection manager).
struct SoloChefView: View {
    let glasses: SolosGlasses
    @State private var model: AppViewModel
    @StateObject private var cameraConnectionListener: CameraConnectionListener
    @State private var showScannerPopup = false

    init(glasses: SolosGlasses) {
        self.glasses = glasses
        _model = State(initialValue: AppViewModel(glasses: glasses))
        _cameraConnectionListener = StateObject(wrappedValue: CameraConnectionListener(glasses: glasses))
    }

    var body: some View {
        ZStack {
            HomeView(model: model, cameraConnected: cameraConnectionListener.isCameraConnected, glasses: glasses)

            if showScannerPopup, glasses.cameraScanner != nil {
                CameraScannerPopup(device: glasses, isPresented: $showScannerPopup)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .overlay(alignment: .bottom) {
            if glasses.cameraScanner != nil, !cameraConnectionListener.isCameraConnected {
                CameraConnectionButton(
                    isShowPopUp: $showScannerPopup,
                    isConnected: cameraConnectionListener.isCameraConnected,
                    glasses: glasses
                )
            }
        }
        .task {
            if glasses.camera == nil, glasses.cameraScanner != nil {
                showScannerPopup = true
            }
        }
    }
}
