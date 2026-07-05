import SwiftUI

// MARK: - LanguagePickerView
struct LanguagePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var langManager = LanguageManager.shared
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(SupportedLanguage.allCases) { lang in
                    Button {
                        langManager.current = lang
                        dismiss()
                    } label: {
                        HStack {
                            Text(lang.flag)
                            Text(lang.displayName)
                            Spacer()
                            if langManager.current == lang {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - CoachChatView
struct CoachChatView: View {
    @Bindable var model: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var messageText = ""
    @StateObject private var speechInput = SpeechInputService()
    @State private var hasAttachedMic = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if let session = model.recipeSession {
                        ForEach(session.messages) { msg in
                            MessageBubble(message: msg)
                        }
                    }
                }
                .padding()
            }

            Divider()

            // Listening indicator
            if speechInput.isListening {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.and.mic")
                        .foregroundStyle(.orange)
                        .symbolEffect(.variableColor.iterative)
                    Text(speechInput.transcript.isEmpty ? "Listening…" : speechInput.transcript)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                    Button("Stop") {
                        speechInput.stopListening()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.08))
            }

            HStack(spacing: 10) {
                TextField("Type a message...", text: $messageText)
                    .textFieldStyle(.roundedBorder)

                // Mic button
                Button {
                    toggleMic()
                } label: {
                    Image(systemName: speechInput.isListening ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.title2)
                        .foregroundStyle(speechInput.isListening ? .red : .orange)
                }
                .disabled(model.isBusy)

                Button {
                    Task { await sendMessage() }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isBusy)
            }
            .padding()
        }
        .navigationTitle("Cooking Coach")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    speechInput.stopListening()
                    dismiss()
                }
            }
        }
        .task {
            await attachMicAndListen()
        }
        .onChange(of: model.pendingAutoListen) { _, shouldListen in
            if shouldListen {
                model.pendingAutoListen = false
                if !model.isBusy {
                    Task { await startListening() }
                }
            }
        }
        .onChange(of: model.isSpeaking) { _, speaking in
            if !speaking && !model.isBusy {
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    await startListening()
                }
            }
        }
        .onDisappear {
            speechInput.stopListening()
        }
    }

    // MARK: - Voice

    private func attachMicAndListen() async {
        #if !targetEnvironment(simulator)
        if !hasAttachedMic, let service = model.glasses as? SolosGlassesService {
            speechInput.attachGlassesMicrophone(service.microphone)
            hasAttachedMic = true
        }
        #endif

        speechInput.onFinalTranscript = { text in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            messageText = ""
            Task { await model.sendCoachMessage(trimmed) }
        }

        // Auto-start listening if the coach isn't speaking
        if !model.isSpeaking && !model.isBusy {
            await startListening()
        }
    }

    private func toggleMic() {
        if speechInput.isListening {
            speechInput.stopAndSubmit()
        } else {
            Task { await startListening() }
        }
    }

    private func startListening() async {
        guard !speechInput.isListening else { return }
        guard !model.isBusy else { return }

        let authorized = await speechInput.requestAuthorization()
        guard authorized else { return }

        do {
            try await speechInput.startListening(allowPhoneFallback: true, micOwner: .coachSTT)
        } catch {
            SoloChefLog.error("stt: coach listen start failed — \(error.localizedDescription)")
        }
    }

    private func sendMessage() async {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messageText = ""
        speechInput.stopListening()
        await model.sendCoachMessage(text)
    }
}

// MARK: - MessageBubble
private struct MessageBubble: View {
    let message: RecipeMessage
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }
            
            Text(message.content)
                .padding(12)
                .background(
                    message.role == .user
                        ? Color.orange
                        : Color(.systemGray5)
                )
                .foregroundStyle(
                    message.role == .user
                        ? .white
                        : .primary
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
            
            if message.role == .assistant {
                Spacer()
            }
        }
    }
}

// MARK: - RecipeResultView
struct RecipeResultView: View {
    @Bindable var model: AppViewModel
    let session: RecipeSession
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(session.dishName)
                    .font(.title.bold())
                
                if !session.recipeText.isEmpty {
                    Text(session.recipeText)
                } else {
                    Text("Recipe is being prepared...")
                        .foregroundStyle(.secondary)
                }
                
                Button {
                    model.showRecipeResult = false
                    model.showCoachChat = true
                } label: {
                    Text("Start cooking with the coach")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding()
        }
        .navigationTitle("Recipe")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - GlassesSnapWaitView
struct GlassesSnapWaitView: View {
    @Bindable var model: AppViewModel
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var hasAutoSnapped = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "eyeglasses")
                .font(.system(size: 60))
                .foregroundStyle(.orange)

            Text("Point your glasses at a dish")
                .font(.title2.bold())

            Text("Auto-snapping in a moment…")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if model.isBusy {
                ProgressView(model.busyMessage)
            }

            if let error = model.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await model.snapDishAndGenerateRecipe() }
            } label: {
                Text("Snap photo")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(model.isBusy || !model.glasses.isConnected)

            Spacer()
        }
        .padding()
        .navigationTitle("Snap a dish")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    onDismiss()
                    dismiss()
                }
            }
        }
        .task {
            guard !hasAutoSnapped else { return }
            hasAutoSnapped = true
            // Give the user a moment to point the glasses, then auto-snap
            try? await Task.sleep(for: .seconds(2))
            guard !model.isBusy, model.glasses.isConnected else { return }
            await model.snapDishAndGenerateRecipe()
        }
        .onChange(of: model.showCoachChat) { _, showing in
            if showing {
                onDismiss()
                dismiss()
            }
        }
    }
}

// MARK: - Passive Voice Commands ViewModifier
extension View {
    func passiveVoiceCommands(model: AppViewModel, isActive: Bool) -> some View {
        self
    }
}

// MARK: - DemoData
enum DemoData {
    static func placeholderImage() -> UIImage {
        let size = CGSize(width: 400, height: 400)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}

#Preview {
    NavigationStack {
        CoachChatView(model: AppViewModel())
    }
}
