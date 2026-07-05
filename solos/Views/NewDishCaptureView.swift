import SwiftUI

struct NewDishCaptureView: View {
    @Bindable var model: AppViewModel
    var onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            // ── Hero ────────────────────────────────────────────────────
            VStack(spacing: 10) {
                Image("SoloChefLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)

                Text("Start cooking")
                    .font(.title2.weight(.bold))

                Text("Snap a dish to identify it, or just tell your chef what you want to make.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .padding(.bottom, 32)

            // ── Thumbnail preview ────────────────────────────────────────
            if let preview = model.lastCapturedThumbnail {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 110, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.orange.opacity(0.3), lineWidth: 2))
                    .padding(.bottom, 20)
            }

            // ── Status ────────────────────────────────────────────────────
            if model.isBusy {
                ProgressView(model.busyMessage)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 20)
            }

            if let error = model.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 8)
            }

            // ── Action buttons ────────────────────────────────────────────
            VStack(spacing: 12) {
                // Primary: snap with glasses
                Button {
                    model.voiceAgentMode = .snapWithGlasses
                    model.isVoiceAgentActive = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "eyeglasses")
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Snap with glasses")
                                .font(.headline)
                            Text("Point glasses at a dish to identify it")
                                .font(.caption)
                                .opacity(0.8)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .opacity(0.6)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(model.isBusy || !model.glasses.isConnected)

                // Secondary: ask by name
                Button {
                    model.voiceAgentMode = .askChef
                    model.isVoiceAgentActive = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "mic.fill")
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ask the chef")
                                .font(.headline)
                            Text("Name a dish and get a guided recipe")
                                .font(.caption)
                                .opacity(0.8)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .opacity(0.6)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .disabled(model.isBusy)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .navigationTitle("New dish")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    onDismiss()
                    dismiss()
                }
            }
        }
        .onChange(of: model.isVoiceAgentActive) { _, active in
            if active {
                onDismiss()
                dismiss()
            }
        }
    }
}

// MARK: - Ask Chef Sheet

private struct AskChefSheet: View {
    @Bindable var model: AppViewModel
    var onDismiss: () -> Void

    @StateObject private var speechInput = SpeechInputService()
    @State private var dishText = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer(minLength: 0)

                VStack(spacing: 8) {
                    Image(systemName: "waveform.and.mic")
                        .font(.system(size: 40))
                        .foregroundStyle(.orange)
                    Text("What would you like to make?")
                        .font(.title3.weight(.semibold))
                    Text("Type a dish name or tap the mic and say it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                // Transcript preview while listening
                if speechInput.isListening, !speechInput.transcript.isEmpty {
                    Text(speechInput.transcript)
                        .font(.body.italic())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Text field
                HStack(spacing: 10) {
                    TextField("e.g. Chicken tikka masala", text: $dishText)
                        .textFieldStyle(.roundedBorder)
                        .focused($focused)
                        .submitLabel(.go)
                        .onSubmit { submit() }

                    // Mic button
                    Button {
                        handleMicTap()
                    } label: {
                        Image(systemName: speechInput.isListening ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(speechInput.isListening ? .red : .orange)
                    }
                    .accessibilityLabel(speechInput.isListening ? "Stop listening" : "Speak dish name")
                }
                .padding(.horizontal)

                // Submit
                Button {
                    submit()
                } label: {
                    Label("Let's cook it", systemImage: "flame.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(dishText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isBusy)
                .padding(.horizontal)

                Spacer(minLength: 0)
            }
            .navigationTitle("Ask the chef")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        speechInput.stopListening()
                        onDismiss()
                        dismiss()
                    }
                }
            }
            .onAppear {
                // Wire transcript back to text field
                speechInput.onFinalTranscript = { text in
                    dishText = text
                }
            }
            .onDisappear {
                speechInput.stopListening()
            }
        }
    }

    private func handleMicTap() {
        if speechInput.isListening {
            speechInput.stopAndSubmit()
        } else {
            Task {
                let authorized = await speechInput.requestAuthorization()
                guard authorized else { return }
                do {
                    try await speechInput.startListening(allowPhoneFallback: true)
                } catch {
                    // ignore
                }
            }
        }
    }

    private func submit() {
        let name = dishText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        focused = false
        speechInput.stopListening()
        onDismiss()
        dismiss()
        Task { await model.askDishByName(name) }
    }
}

#Preview {
    NavigationStack {
        NewDishCaptureView(model: AppViewModel(), onDismiss: {})
    }
}
