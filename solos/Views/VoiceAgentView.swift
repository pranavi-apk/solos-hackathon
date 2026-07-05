import SwiftUI

struct VoiceAgentView: View {
    @Bindable var model: AppViewModel
    let mode: VoiceAgentController.Mode
    @Environment(\.dismiss) private var dismiss
    
    @State private var controller: VoiceAgentController?
    @State private var isPulseActive = false
    
    var body: some View {
        ZStack {
            // Curated deep dark aesthetic gradient background
            LinearGradient(
                colors: [Color(red: 18/255, green: 18/255, blue: 24/255), Color(red: 28/255, green: 28/255, blue: 38/255)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 32) {
                // Header with custom design
                HStack {
                    Button {
                        controller?.stop()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    
                    Text("SoloChef AI Agent")
                        .font(.headline)
                        .foregroundStyle(.white)
                    
                    Spacer()
                    
                    // Connected Glasses Icon indicator
                    Image(systemName: model.glasses.isConnected ? "eyeglasses" : "eyeglasses.slash")
                        .font(.headline)
                        .foregroundStyle(model.glasses.isConnected ? .green : .orange)
                }
                .padding(.horizontal)
                .padding(.top, 16)
                
                Spacer()
                
                // Visual Waveform / Pulse State Indicator
                ZStack {
                    Circle()
                        .stroke(gradientForState().opacity(0.2), lineWidth: 4)
                        .frame(width: 180, height: 180)
                        .scaleEffect(isPulseActive ? 1.25 : 1.0)
                        .opacity(isPulseActive ? 0.0 : 1.0)
                    
                    Circle()
                        .fill(gradientForState())
                        .frame(width: 140, height: 140)
                        .shadow(color: shadowColorForState(), radius: 20)
                    
                    // Icon matching the active state
                    Image(systemName: iconForState())
                        .font(.system(size: 48))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: isPulseActive)
                }
                .padding(.bottom, 20)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                        isPulseActive = true
                    }
                }
                
                // Text status
                VStack(spacing: 8) {
                    Text(statusTitleForState())
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    
                    if let ctrl = controller {
                        Text(ctrl.statusMessage)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                        
                        if !ctrl.transcript.isEmpty {
                            Text("\"\(ctrl.transcript)\"")
                                .font(.body.italic())
                                .foregroundStyle(.orange)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                                .padding(.top, 8)
                                .lineLimit(3)
                        }
                    }
                }
                
                Spacer()
                
                // Informational hint
                VStack(spacing: 4) {
                    Text(informationalHint())
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    
                    if let error = controller?.errorMessage {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .padding(.top, 4)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            let ctrl = VoiceAgentController(mode: mode, model: model)
            controller = ctrl
            Task {
                await ctrl.start()
            }
        }
        .onDisappear {
            controller?.stop()
        }
    }
    
    // MARK: - State styling helpers
    
    private func gradientForState() -> LinearGradient {
        guard let state = controller?.state else {
            return LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom)
        }
        switch state {
        case .listening:
            return LinearGradient(colors: [.green, .teal], startPoint: .top, endPoint: .bottom)
        case .thinking:
            return LinearGradient(colors: [.purple, .indigo], startPoint: .top, endPoint: .bottom)
        case .speaking:
            return LinearGradient(colors: [.blue, .cyan], startPoint: .top, endPoint: .bottom)
        case .takingPhoto:
            return LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
        case .idle:
            return LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom)
        }
    }
    
    private func shadowColorForState() -> Color {
        guard let state = controller?.state else { return .orange }
        switch state {
        case .listening: return .green.opacity(0.5)
        case .thinking: return .purple.opacity(0.5)
        case .speaking: return .blue.opacity(0.5)
        case .takingPhoto: return .orange.opacity(0.5)
        case .idle: return .orange.opacity(0.5)
        }
    }
    
    private func iconForState() -> String {
        guard let state = controller?.state else { return "mic.fill" }
        switch state {
        case .listening: return "waveform.and.mic"
        case .thinking: return "ellipsis.bubble.fill"
        case .speaking: return "speaker.wave.3.fill"
        case .takingPhoto: return "camera.fill"
        case .idle: return "mic.fill"
        }
    }
    
    private func statusTitleForState() -> String {
        guard let state = controller?.state else { return "SoloChef Agent" }
        switch state {
        case .listening: return "Listening"
        case .thinking: return "Thinking..."
        case .speaking: return "Speaking"
        case .takingPhoto: return "Taking Photo"
        case .idle: return "Ready"
        }
    }
    
    private func informationalHint() -> String {
        guard let state = controller?.state else { return "" }
        switch state {
        case .listening:
            return "Talk normally. When you stop speaking for 2 seconds, I will automatically process it."
        case .speaking:
            return "Start speaking anytime to barge-in and interrupt me."
        default:
            return "Hands-free continuous mode is active."
        }
    }
}
