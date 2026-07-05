import SwiftUI
import UIKit
import SolosAirGoSDK

@MainActor
@Observable
final class AppViewModel {
    let glasses: GlassesService
    var isBusy = false
    var busyMessage = "Identifying dish and writing recipe…"
    var lastError: String?
    var recipeSession: RecipeSession?
    var showRecipeResult = false
    var showCoachChat = false
    var offerPhoneCaptureFallback = false

    private let coach = CookingCoachService()

    init(glasses: SolosGlasses) {
        self.glasses = ConnectedGlassesService(glasses: glasses)
    }

    var isGlassesWifiConnected: Bool {
        glasses.isWifiConnected
    }

    var prefersPhoneCapture: Bool {
        !isGlassesWifiConnected || offerPhoneCaptureFallback
    }

    func snapDishAndGenerateRecipe() async {
        guard glasses.isConnected else {
            lastError = GlassesServiceError.notConnected.localizedDescription
            return
        }
        guard glasses.isCameraReady else {
            lastError = GlassesServiceError.cameraUnavailable.localizedDescription
            return
        }

        isBusy = true
        busyMessage = "Taking photo with glasses…"
        lastError = nil
        defer { isBusy = false }

        do {
            let image = try await glasses.takePhoto()
            try await generateRecipe(from: image)
        } catch {
            lastError = GlassesPhotoErrorMapper.userMessage(for: error)
            if GlassesPhotoErrorMapper.isWifiPhotoFailure(error) {
                offerPhoneCaptureFallback = true
            }
        }
    }

    func snapWithPhoneCameraAndGenerateRecipe() async {
        isBusy = true
        busyMessage = "Opening phone camera…"
        lastError = nil
        defer { isBusy = false }

        do {
            let image = try await PhoneCameraCapture.captureFromDeviceCamera()
            busyMessage = "Identifying dish and writing recipe…"
            try await generateRecipe(from: image)
        } catch PhoneCameraCapture.CaptureError.cancelled {
            // User dismissed camera.
        } catch {
            lastError = error.localizedDescription
        }
    }

    func pickPhotoFromLibraryAndGenerateRecipe() async {
        isBusy = true
        busyMessage = "Opening photo library…"
        lastError = nil
        defer { isBusy = false }

        do {
            let image = try await PhoneCameraCapture.pickFromPhotoLibrary()
            busyMessage = "Identifying dish and writing recipe…"
            try await generateRecipe(from: image)
        } catch PhoneCameraCapture.CaptureError.cancelled {
            // User dismissed picker.
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func generateRecipe(from image: UIImage) async throws {
        busyMessage = "Identifying dish and writing recipe…"
        let session = try await coach.identifyAndGenerateRecipe(from: image)
        recipeSession = session
        showRecipeResult = true
        offerPhoneCaptureFallback = false
        await glasses.speak(session.spokenIntro)
    }

    func askFollowUp(_ question: String) async {
        guard var session = recipeSession else { return }

        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isBusy = true
        busyMessage = "Chef is thinking…"
        lastError = nil
        defer { isBusy = false }

        do {
            let answer = try await coach.askFollowUp(session: &session, question: trimmed)
            recipeSession = session
            await glasses.speak(answer)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func startNewDish() {
        recipeSession = nil
        showRecipeResult = false
        showCoachChat = false
        lastError = nil
        offerPhoneCaptureFallback = !isGlassesWifiConnected
    }
}
