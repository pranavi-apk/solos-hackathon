import UIKit
import SolosAirGoSDK

/// Wraps the demo's connected `SolosGlasses` for photo capture and speaker output.
protocol GlassesService: AnyObject {
    var isConnected: Bool { get }
    var deviceName: String? { get }
    var isCameraReady: Bool { get }
    var isWifiConnected: Bool { get }

    func takePhoto() async throws -> UIImage
    func speak(_ text: String) async
}

enum GlassesServiceError: LocalizedError {
    case notConnected
    case captureFailed
    case wifiRequiredForPhoto
    case audioFailed
    case cameraUnavailable

    var errorDescription: String? {
        switch self {
        case .notConnected:
            "Glasses are not connected. Go back and reconnect."
        case .captureFailed:
            "Could not capture a photo from the glasses."
        case .wifiRequiredForPhoto:
            """
            Photo captured on glasses but could not download — Wi-Fi is not connected. \
            Use the phone camera button below, or join Wi-Fi on iPhone and connect in the Wi-Fi demo.
            """
        case .audioFailed:
            "Could not play audio on the glasses."
        case .cameraUnavailable:
            "Glasses camera is not connected. Tap Connect Camera below, then try again."
        }
    }
}

enum GlassesPhotoErrorMapper {
    static func userMessage(for error: Error) -> String {
        if let cameraError = error as? SolosCameraError {
            switch cameraError {
            case .photoTakenButUnreachable:
                return GlassesServiceError.wifiRequiredForPhoto.localizedDescription
            default:
                return cameraError.errorDescription
            }
        }
        if let wifiError = error as? WiFiError, case .wifiNotConnected = wifiError {
            return GlassesServiceError.wifiRequiredForPhoto.localizedDescription
        }
        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("wifi")
            || message.localizedCaseInsensitiveContains("wi-fi")
            || message.localizedCaseInsensitiveContains("unreachable")
            || message.localizedCaseInsensitiveContains("retrieve") {
            return GlassesServiceError.wifiRequiredForPhoto.localizedDescription
        }
        return message
    }

    static func isWifiPhotoFailure(_ error: Error) -> Bool {
        if let serviceError = error as? GlassesServiceError, case .wifiRequiredForPhoto = serviceError {
            return true
        }
        if let cameraError = error as? SolosCameraError, case .photoTakenButUnreachable = cameraError {
            return true
        }
        if let wifiError = error as? WiFiError, case .wifiNotConnected = wifiError {
            return true
        }
        return GlassesPhotoErrorMapper.userMessage(for: error)
            == GlassesServiceError.wifiRequiredForPhoto.localizedDescription
    }
}

@MainActor
final class ConnectedGlassesService: GlassesService {
    private let glasses: SolosGlasses

    init(glasses: SolosGlasses) {
        self.glasses = glasses
    }

    var isConnected: Bool { glasses.status == .connected }
    var deviceName: String? { glasses.name }
    var isCameraReady: Bool { glasses.camera != nil }
    var isWifiConnected: Bool { glasses.wifi?.status == .connected }

    func takePhoto() async throws -> UIImage {
        guard isConnected else { throw GlassesServiceError.notConnected }
        guard let camera = glasses.camera else {
            throw GlassesServiceError.cameraUnavailable
        }

        let config = PhotoConfiguration.highQualityConfiguration(resolution: ._1280_960)
        let photo = try await camera.photo(with: config)
        guard let image = UIImage(data: photo.data) else {
            throw GlassesServiceError.captureFailed
        }
        return image
    }

    func speak(_ text: String) async {
        guard isConnected else {
            await SpeechService.shared.speak(text)
            return
        }
        guard let speaker = glasses.audio?.speaker else {
            await SpeechService.shared.speak(text)
            return
        }

        do {
            try await GlassesAudioPlayer.speakOnGlasses(text, speaker: speaker)
        } catch {
            await SpeechService.shared.speak(text)
        }
    }
}
