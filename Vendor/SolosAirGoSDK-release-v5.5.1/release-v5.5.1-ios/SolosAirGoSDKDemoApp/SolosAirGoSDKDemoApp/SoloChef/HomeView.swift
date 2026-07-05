import SwiftUI
import SolosAirGoSDK

struct HomeView: View {
    @Bindable var model: AppViewModel
    var cameraConnected: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header

                if !cameraConnected {
                    cameraHint
                }

                if model.prefersPhoneCapture {
                    wifiFallbackBanner
                    phoneCaptureButton
                    libraryButton
                    if model.isGlassesWifiConnected, cameraConnected {
                        glassesCaptureButton
                    }
                } else if cameraConnected {
                    glassesCaptureButton
                    phoneCaptureButtonSecondary
                }

                if model.isBusy {
                    ProgressView(model.busyMessage)
                        .multilineTextAlignment(.center)
                }

                if let error = model.lastError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)

                    if model.offerPhoneCaptureFallback {
                        phoneCaptureButton
                        libraryButton
                    }
                }

                tipsCard
            }
            .padding(20)
        }
        .navigationTitle("SoloChef")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $model.showRecipeResult) {
            if let session = model.recipeSession {
                RecipeResultView(model: model, session: session)
            }
        }
        .onAppear {
            if !model.isGlassesWifiConnected {
                model.offerPhoneCaptureFallback = true
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "frying.pan.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text("Snap a dish, get a recipe")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            if let name = model.glasses.deviceName {
                Text("Connected to \(name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(headerSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var headerSubtitle: String {
        if model.prefersPhoneCapture {
            "Wi-Fi is not connected on the glasses — use your phone camera. Recipe readout still plays on the glasses speaker."
        } else {
            "Point your glasses at food — a photo, plate, or cookbook picture — and SoloChef will tell you how to make it."
        }
    }

    private var cameraHint: some View {
        Label("Connect the glasses camera below before snapping a dish.", systemImage: "camera.badge.ellipsis")
            .font(.subheadline)
            .foregroundStyle(.orange)
            .multilineTextAlignment(.center)
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private var wifiFallbackBanner: some View {
        Label(SolosConfig.v2PhotoRequiresWiFiHint, systemImage: "wifi.slash")
            .font(.subheadline)
            .foregroundStyle(.orange)
            .multilineTextAlignment(.center)
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private var glassesCaptureButton: some View {
        Button {
            Task { await model.snapDishAndGenerateRecipe() }
        } label: {
            VStack(spacing: 12) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 48))
                Text("What is this meal?")
                    .font(.title.bold())
                Text("Snap with glasses")
                    .font(.subheadline)
                    .opacity(0.9)
            }
            .frame(maxWidth: .infinity, minHeight: 160)
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .disabled(model.isBusy || !cameraConnected)
        .accessibilityHint("Takes a photo with your glasses and generates a home-cook recipe")
    }

    private var phoneCaptureButton: some View {
        Button {
            Task { await model.snapWithPhoneCameraAndGenerateRecipe() }
        } label: {
            VStack(spacing: 12) {
                Image(systemName: "iphone")
                    .font(.system(size: 40))
                Text("Use phone camera")
                    .font(.title3.bold())
                Text(model.isGlassesWifiConnected ? "Glasses photo unavailable" : "Wi-Fi unavailable")
                    .font(.subheadline)
                    .opacity(0.9)
            }
            .frame(maxWidth: .infinity, minHeight: 140)
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)
        .disabled(model.isBusy)
        .accessibilityHint("Takes a photo with your iPhone camera and generates a recipe using the same AI coach")
    }

    private var phoneCaptureButtonSecondary: some View {
        Button {
            Task { await model.snapWithPhoneCameraAndGenerateRecipe() }
        } label: {
            Label("Use phone camera instead", systemImage: "iphone")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(model.isBusy)
    }

    private var libraryButton: some View {
        Button {
            Task { await model.pickPhotoFromLibraryAndGenerateRecipe() }
        } label: {
            Label("Choose photo from library", systemImage: "photo.on.rectangle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(model.isBusy)
    }

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Demo tips", systemImage: "lightbulb.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            Text("• Point at a photo of pasta, cake, or any dish")
            Text("• Hear the recipe on your glasses speaker")
            Text("• Ask follow-ups like “Can I substitute butter?”")
            if model.prefersPhoneCapture {
                Text("• For glasses POV: join Wi-Fi on iPhone → Wi-Fi demo → Connect")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
