import Foundation
#if !targetEnvironment(simulator)
@preconcurrency import SolosAirGoSDK
#endif

/// Solos glasses pairing — change `targetGlassesNameSuffix` for your unit at the competition.
enum SolosConfig {
    /// Last segment of the BLE advertised name, e.g. `01F0` in `Solos AirGoV2 01F0`.
    static var targetGlassesNameSuffix: String {
        get {
            UserDefaults.standard.string(forKey: "SolosTargetGlassesNameSuffix") ?? "01F0"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "SolosTargetGlassesNameSuffix")
        }
    }

    static var targetDisplayName: String {
        "Solos AirGoV2 \(targetGlassesNameSuffix)"
    }

    /// Glasses soft-AP fallback SSID (suffix matches BLE name). Primary path: same home/class Wi-Fi as iPhone.
    static var expectedHotspotSSID: String {
        "Solos-\(targetGlassesNameSuffix)"
    }

    /// AirGo V2 built-in camera stores photos on-glasses; `photo(with:)` downloads them over Wi-Fi only.
    static let v2PhotoRequiresWiFiHint =
        "Glasses photos need Wi-Fi. Connect glasses to your iPhone hotspot below, then snap."

    /// One-line hint on Connect and Home.
    static let wifiPhotoOneLiner =
        "Glasses photos download over Wi-Fi — connect hotspot first."

    /// Shown on the in-app Wi-Fi card (full mode).
    static let homeWiFiHint =
        "Connect glasses to your iPhone Personal Hotspot for on-glasses photos. Keep the Hotspot screen open in Settings while connecting."

    /// One-tap connect button on ConnectView and Home Wi-Fi card.
    static let competitionHotspotButtonLabel = "Connect to iPhone hotspot"

    /// Countdown before auto-connect — user enables hotspot first, then taps Prepare.
    static let competitionHotspotPrepareButtonLabel = "Prepare hotspot, then connect"

    /// Seconds to wait on Personal Hotspot screen before auto-connect.
    static let hotspotPrepareCountdownSeconds: TimeInterval = 15

    /// Compact hint on ConnectView Wi-Fi card only — keep login screen uncluttered.
    static let competitionHotspotCompactHint =
        "Settings → Personal Hotspot → Allow Others to Join. Stay on that screen, tap Prepare, wait 15 s."

    /// Instruction shown during hotspot prepare countdown.
    static let hotspotPrepareInstruction =
        "Keep Settings → Personal Hotspot open until the countdown finishes."

    /// Saved hotspot credentials from gitignored Secrets.swift (or DEFAULT_WIFI_* env vars).
    static var competitionHotspotSSID: String? { Secrets.resolvedDefaultWiFiSSID }

    static var competitionHotspotPassword: String? { Secrets.resolvedDefaultWiFiPassword }

    static var hasCompetitionHotspotCredentials: Bool {
        guard let ssid = competitionHotspotSSID, !ssid.isEmpty,
              let password = competitionHotspotPassword, !password.isEmpty else {
            return false
        }
        return true
    }

    static func isCompetitionHotspotSSID(_ ssid: String?) -> Bool {
        guard let configured = competitionHotspotSSID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !configured.isEmpty,
              let candidate = ssid?.trimmingCharacters(in: .whitespacesAndNewlines),
              !candidate.isEmpty else {
            return false
        }
        return candidate.caseInsensitiveCompare(configured) == .orderedSame
    }

    /// Shown when glasses fail to join the configured iPhone hotspot.
    static func competitionHotspotFailureHint(exactSSID: String) -> String {
        """
        iPhone Personal Hotspot can be slow for the glasses Wi-Fi chip (QCC5126). connectionTimeout with bleDroppedDuringConnect=false usually means the hotspot never accepted the glasses — not a wrong password.

        Retry: stay on Settings → Personal Hotspot, tap Prepare hotspot then connect, and wait for the full countdown. Enable Maximize Compatibility (2.4 GHz) if available.

        SSID must match exactly: "\(exactSSID)". If it still fails, try a dedicated 2.4 GHz router or Android hotspot.
        """
    }

    /// Seconds to wait for BLE scan fallback (Settings-first path tries serial connect first).
    static let scanTimeoutSeconds: TimeInterval = 30

    /// Demo DirectConnectionTab uses 60s for `connectGlasses(withSerialNumber:timeout:)`.
    static let connectTimeoutSeconds: TimeInterval = 60

    /// Max wait for `CBCentralManager` to reach `.poweredOn` before connect/scan.
    static let bluetoothReadinessTimeoutSeconds: TimeInterval = 15

    /// Pause after SDK Gaia `poweredOn` so internal BLE stack finishes warm-up (demo tap delay).
    static let gaiaReadyDelayMilliseconds: UInt64 = 750

    /// Max wait for SDK Gaia `GaiaManagerNotification` `poweredOn` after scanner pre-warm.
    static let gaiaReadinessTimeoutSeconds: TimeInterval = 15

    /// Status poll interval while waiting for Gaia transport.
    static let connectStatusPollSeconds: TimeInterval = 5

    /// After GlassesStatus becomes `.connected`, wait this long before enabling SDK features.
    static let transportStabilitySeconds: TimeInterval = 1.5

    /// Poll interval during the post-connect stability window.
    static let transportStabilityPollSeconds: TimeInterval = 0.5

    /// Pause before connecting on non-hotspot networks (lets QCC5126 finish boot).
    static let wifiConnectPreDelaySeconds: TimeInterval = 8

    /// Longer pre-connect pause for iPhone Personal Hotspot — AP needs time to accept clients.
    static let wifiConnectHotspotPreDelaySeconds: TimeInterval = 18

    /// Base pause before each automatic retry when SDK returns `connectionTimeout` (multiplied by attempt index).
    static let wifiConnectRetryDelaySeconds: TimeInterval = 3

    /// Longer retry spacing for iPhone hotspot (AP may need extra time to accept the glasses).
    static let wifiConnectHotspotRetryDelaySeconds: TimeInterval = 9

    /// When true, match vendor WiFiDemo: no pre-delay, no auto-retry, no BLE poll, delegate-only attach during connect.
    static let wifiSimpleConnectMode = false

    static func wifiConnectPreDelay(for ssid: String?) -> TimeInterval {
        // Even in simple mode, personal hotspots require a pre-delay to advertise and accept incoming clients.
        return isCompetitionHotspotSSID(ssid) ? wifiConnectHotspotPreDelaySeconds : (wifiSimpleConnectMode ? 0 : wifiConnectPreDelaySeconds)
    }

    static func wifiConnectRetryDelay(for ssid: String?) -> TimeInterval {
        isCompetitionHotspotSSID(ssid) ? wifiConnectHotspotRetryDelaySeconds : wifiConnectRetryDelaySeconds
    }

    /// Automatic retries after `connectionTimeout` — disconnect stale Wi-Fi before each retry (legacy mode only).
    static let wifiConnectMaxAutoRetriesLegacy = 3

    static func wifiConnectMaxAutoRetries(for ssid: String? = nil) -> Int {
        // Personal hotspots need more retry attempts because the iPhone hotspot AP can cycle on/off.
        if isCompetitionHotspotSSID(ssid) { return 3 }
        if wifiSimpleConnectMode { return 1 }
        return wifiConnectMaxAutoRetriesLegacy
    }

    /// Poll interval while logging BLE status during an in-flight Wi-Fi connect.
    static let wifiConnectBlePollSeconds: TimeInterval = 2

    /// Shown when SSID looks like campus / enterprise Wi-Fi.
    static let campusWiFiBanner =
        "Campus Wi-Fi often fails on glasses — use iPhone hotspot or home Wi-Fi for dish photos."

    /// Pause before retrying after a failed serial connect (lets iOS release the BLE link).
    static let reconnectCooldownSeconds: TimeInterval = 2

    /// Max wait for glasses camera capture + Wi-Fi FTP download (`camera.photo(with:)`).
    static let glassesPhotoTimeoutSeconds: TimeInterval = 45

    /// Max wait for Mistral vision identify-dish call (includes upload + inference).
    static let identifyDishTimeoutSeconds: TimeInterval = 60

    /// Seconds of silence after speech before auto-submitting STT (VAD end-of-utterance).
    static let vadSilenceTimeoutSeconds: TimeInterval = 2

    /// RMS energy threshold for barge-in detection on glasses mic PCM buffers.
    static let bargeInEnergyThreshold: Float = 0.028

    /// Consecutive energetic buffers required before treating speech as barge-in.
    static let bargeInConsecutiveBuffers = 6

    /// Ignore barge-in for this long after TTS starts (avoids false triggers from coach playback).
    static let bargeInGracePeriodSeconds: TimeInterval = 2.5

    /// Max characters per TTS utterance before splitting on sentence boundaries.
    static let ttsMaxChunkCharacters = 280

    /// Shown when glasses are not bonded in iOS Settings.
    static var pairInSettingsHint: String {
        "Pair \(targetDisplayName) in iPhone Settings → Bluetooth first, then return to SoloChef."
    }

    /// Troubleshooting when connect stalls after pairing.
    static var forgetDeviceHint: String {
        "If connection keeps failing, open Settings → Bluetooth, tap ⓘ on \(targetDisplayName), choose Forget This Device, pair again, then reopen SoloChef."
    }

    /// Shown when BLE drops during the Gaia handshake (often stale Settings bond).
    static var handshakeDisconnectHint: String {
        "Connection dropped during setup. \(forgetDeviceHint) Power-cycle the glasses, then try again."
    }

    /// Shown when an established link drops (often glasses auto-sleep between classes).
    static let glassesSleepHint =
        "Glasses disconnected — they may have auto-slept. Put them on or say “Hey Solos”, then tap Retry connection."

    /// Match competition glasses by BLE advertised **name** suffix (e.g. `01F0` in `Solos AirGoV2 01F0`).
    static func matchesTargetDevice(name: String) -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.hasSuffix(targetGlassesNameSuffix)
            || normalized.localizedCaseInsensitiveContains(" \(targetGlassesNameSuffix)")
    }

    static func matchesTargetGlasses(_ glasses: SolosAirGoSDK.SolosGlasses) -> Bool {
        matchesTargetDevice(name: glasses.name)
    }

    private(set) static var isSDKConfigured = false

    /// Call once at app launch before creating Manager / Scanner (demo ContentView.onAppear pattern).
    @MainActor
    static func configureSDKIfNeeded() {
        guard !isSDKConfigured else { return }
        SolosSdkLibrary.configure()
        isSDKConfigured = true
        BluetoothReadinessMonitor.shared.warmUp()
        // Demo creates Scanner in init — pre-warm so SDK Gaia CBCentralManager powers on before Connect.
        SolosConnectionManager.shared.preWarmScanner()
        print("[Solos] SDK configured — version \(SolosSdkLibrary.getSdkVersion())")
    }
}
