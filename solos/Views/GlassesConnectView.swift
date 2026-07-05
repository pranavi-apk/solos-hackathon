import SwiftUI
import UIKit
#if !targetEnvironment(simulator)
@preconcurrency import SolosAirGoSDK
#endif

struct GlassesConnectView: View {
    @Bindable var model: AppViewModel
    @Bindable private var connection = SolosConnectionManager.shared
    @Bindable private var wifiMonitor = GlassesWiFiMonitor.shared

    @State private var showKitchen = false
    @State private var showWiFiSheet = false
    @State private var wiFiSSID = ""
    @State private var wiFiPassword = ""

    private var bluetoothConnected: Bool {
        connection.isConnected || model.glasses.isConnected
    }

    private var bluetoothSubtitle: String {
        if bluetoothConnected {
            if let name = model.connectedGlassesName ?? connection.connectedGlasses?.name {
                return "Connected to \(name)"
            }
            return "Bluetooth connected"
        }

        switch connection.connectionPhase {
        case .scanning:
            return "Scanning for glasses…"
        case .connecting:
            if let name = connection.connectedGlasses?.name ?? model.connectedGlassesName {
                return "Connecting to \(name)…"
            }
            return "Connecting…"
        default:
            if let error = model.lastError, !error.isEmpty {
                return error
            }
            return "Tap to connect your glasses"
        }
    }

    private var wifiConnected: Bool {
        wifiMonitor.isConnected
    }

    private var wifiSubtitle: String {
        if wifiConnected {
            if let ssid = wifiMonitor.connectedSSID, !ssid.isEmpty {
                return "Connected to \(ssid)"
            }
            return "Connected to home network"
        }
        if model.isWifiConnecting {
            return "Connecting to Wi‑Fi…"
        }
        if let error = model.wifiError, !error.isEmpty {
            return error
        }
        return "Tap to join your hotspot"
    }

    private var canEnterKitchen: Bool {
        bluetoothConnected && wifiConnected
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 32) {
                    Spacer().frame(height: 32)

                    logoView
                        .padding(.top, 16)

                    Text("SoloChef")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.top, 4)

                    VStack(spacing: 16) {
                        statusCard(
                            title: model.connectedGlassesName ?? "Solos AirGoV2",
                            subtitle: bluetoothSubtitle,
                            systemImage: "antenna.radiowaves.left.and.right",
                            isConnected: bluetoothConnected,
                            isBusy: connection.connectionPhase == .scanning || connection.connectionPhase == .connecting,
                            tint: .green
                        ) {
                            Task { await model.connectGlasses() }
                        }

                        statusCard(
                            title: wifiMonitor.connectedSSID ?? "Wi‑Fi",
                            subtitle: wifiSubtitle,
                            systemImage: "wifi",
                            isConnected: wifiConnected,
                            isBusy: model.isWifiConnecting,
                            tint: .green
                        ) {
                            showWiFiSheet = true
                        }
                    }
                    .padding(.horizontal, 20)

                    if let lastError = model.lastError,
                       !lastError.isEmpty,
                       !bluetoothConnected {
                        Text(lastError)
                            .font(.callout)
                            .foregroundStyle(.red.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    if let wifiError = model.wifiError,
                       !wifiError.isEmpty,
                       !wifiConnected {
                        Text(wifiError)
                            .font(.callout)
                            .foregroundStyle(.red.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    Button {
                        model.didEnterKitchen = true
                        showKitchen = true
                    } label: {
                        Label("Enter Kitchen", systemImage: "fork.knife")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(canEnterKitchen ? Color.orange : Color.orange.opacity(0.4))
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .padding(.horizontal, 32)
                    .disabled(!canEnterKitchen)
                    .padding(.top, 8)

                    Spacer()

                    if model.isBusy {
                        ProgressView(model.busyMessage.isEmpty ? "Working…" : model.busyMessage)
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .padding(.bottom, 24)
                    } else {
                        Spacer().frame(height: 24)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showKitchen) {
                KitchenView(model: model)
            }
        }
        .sheet(isPresented: $showWiFiSheet) {
            NavigationStack {
                Form {
                    Section(header: Text("Hotspot credentials")) {
                        TextField("Wi‑Fi Network Name", text: $wiFiSSID)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        SecureField("Wi‑Fi Password", text: $wiFiPassword)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }

                    if let wifiError = model.wifiError, !wifiError.isEmpty {
                        Section {
                            Text(wifiError)
                                .foregroundStyle(.red)
                        }
                    }

                    Section(footer: Text("Make sure your iPhone hotspot stays on screen while pairing.")) {
                        EmptyView()
                    }
                }
                .navigationTitle("Connect Wi‑Fi")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            showWiFiSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            Task {
                                await model.connectGlassesToHomeWiFi(
                                    ssid: wiFiSSID,
                                    password: wiFiPassword,
                                    monitor: wifiMonitor
                                )
                                if wifiMonitor.isConnected {
                                    showWiFiSheet = false
                                }
                                if model.wifiNeedsFreshPassword {
                                    wiFiPassword = ""
                                }
                            }
                        } label: {
                            if model.isWifiConnecting {
                                ProgressView()
                            } else {
                                Text(wifiConnected ? "Update" : "Connect")
                            }
                        }
                        .disabled(model.isWifiConnecting)
                    }
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .onAppear(perform: configureDefaults)
        .onChange(of: wifiMonitor.isConnected) { connected in
            if connected {
                showWiFiSheet = false
            }
        }
    }

    @ViewBuilder
    private var logoView: some View {
        if let image = UIImage(named: "SoloChefLogo") {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 160, height: 110)
                .shadow(color: .orange.opacity(0.45), radius: 12, y: 6)
        } else {
            Image(systemName: "glasses")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 70)
                .foregroundStyle(.orange)
        }
    }

    private func statusCard(
        title: String,
        subtitle: String,
        systemImage: String,
        isConnected: Bool,
        isBusy: Bool,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(isConnected ? tint.opacity(0.2) : Color.white.opacity(0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isConnected ? tint : .white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(isConnected ? tint : .white.opacity(0.7))
                        .lineLimit(2)
                }

                Spacer()

                if isConnected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(tint)
                } else if isBusy {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(red: 34/255, green: 34/255, blue: 34/255))
            )
        }
        .buttonStyle(.plain)
    }

    private func configureDefaults() {
        #if !targetEnvironment(simulator)
        SolosConfig.configureSDKIfNeeded()
        #endif

        if wiFiSSID.isEmpty, let hotspot = SolosConfig.competitionHotspotSSID {
            wiFiSSID = hotspot
        }
        if wiFiPassword.isEmpty, let password = SolosConfig.competitionHotspotPassword {
            wiFiPassword = password
        }
    }
}

#Preview {
    GlassesConnectView(model: AppViewModel())
}
