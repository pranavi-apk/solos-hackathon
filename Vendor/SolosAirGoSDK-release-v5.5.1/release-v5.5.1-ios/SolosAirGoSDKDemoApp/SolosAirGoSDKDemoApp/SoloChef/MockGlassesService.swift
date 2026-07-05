import UIKit

/// Demo path: no BLE/Wi-Fi — always "connected", speaks via iPhone TTS.
@MainActor
final class MockGlassesService: GlassesService {
    var isConnected: Bool { true }
    var deviceName: String? { "SoloChef Demo (iPhone speaker)" }
    var isCameraReady: Bool { true }

    func takePhoto() async throws -> UIImage {
        try await Task.sleep(for: .milliseconds(300))
        return DemoData.placeholderImage()
    }

    func speak(_ text: String) async {
        SpeechService.shared.speak(text)
    }
}
