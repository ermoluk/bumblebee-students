import SwiftUI
import AppKit

enum Section: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case entertainment = "Entertainment"
    case settings = "Settings"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.bottom.50percent"
        case .entertainment: return "music.note"
        case .settings: return "wifi"
        }
    }
}

@main
struct GCSMacApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(app.scanner)
                .environmentObject(app.telemetry)
                .environmentObject(app.metrics)
                .environmentObject(app.handoff)
                .frame(minWidth: 1100, minHeight: 720)
                .preferredColorScheme(.dark)
                .onAppear {
                    app.scanner.startDiscovery()   // continuous Bonjour/mDNS
                    app.scanner.scan()              // one-shot subnet fallback
                    app.handoff.requestLocation()   // settle WiFi-scan permission up front
                    DockIcon.install()
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Reconnect") { app.reconnect() }.keyboardShortcut("r", modifiers: .command)
                Button("Rescan Network") { app.scanner.scan() }.keyboardShortcut("k", modifiers: .command)
                Button("Disconnect") { app.disconnect() }.keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }
    }
}

/// A drone the operator has connected to before — remembered across launches so
/// the fleet shows up by name without a fresh scan.
struct KnownDrone: Codable, Identifiable, Equatable {
    var id: String { host }   // ip/host, stable
    var host: String
    var name: String
}

@MainActor
final class AppState: ObservableObject {
    let scanner = DroneScanner()
    let telemetry = TelemetryStore()
    let metrics = MetricsClient()
    let api = DroneAPI()
    let handoff = WifiHandoff()
    private(set) lazy var ros = RosbridgeClient(store: telemetry)

    @Published var droneHost = ""
    @Published var connected = false
    @Published var lastHost: String? = UserDefaults.standard.string(forKey: "lastHost")
    @Published var knownDrones: [KnownDrone] = AppState.loadKnown()

    private var activity: NSObjectProtocol?
    private static let knownKey = "knownDrones"

    func connect(to ip: String) {
        let ip = ip.trimmingCharacters(in: .whitespaces)
        guard !ip.isEmpty else { return }
        droneHost = ip
        api.host = ip
        ros.connect(host: ip)
        metrics.start(host: ip)
        connected = true
        lastHost = ip
        UserDefaults.standard.set(ip, forKey: "lastHost")
        rememberDrone(host: ip)
        beginKeepAwake()
    }

    /// Upsert a drone into the remembered fleet, keyed by host. Prefers a
    /// Bonjour-provided friendly name when the scanner has one.
    private func rememberDrone(host: String) {
        let name = scanner.found.first(where: { $0.ip == host })?.name ?? host
        if let idx = knownDrones.firstIndex(where: { $0.host == host }) {
            if name != host { knownDrones[idx].name = name }
        } else {
            knownDrones.append(KnownDrone(host: host, name: name))
        }
        if let data = try? JSONEncoder().encode(knownDrones) {
            UserDefaults.standard.set(data, forKey: Self.knownKey)
        }
    }

    private static func loadKnown() -> [KnownDrone] {
        guard let data = UserDefaults.standard.data(forKey: knownKey),
              let list = try? JSONDecoder().decode([KnownDrone].self, from: data) else { return [] }
        return list
    }

    func reconnect() {
        guard connected, !droneHost.isEmpty else { return }
        ros.connect(host: droneHost)
        metrics.start(host: droneHost)
    }

    func disconnect() {
        ros.disconnect()
        metrics.stop()
        connected = false
        endKeepAwake()
    }

    private func beginKeepAwake() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled, .userInitiated], reason: "Drone live video")
    }
    private func endKeepAwake() {
        if let a = activity { ProcessInfo.processInfo.endActivity(a); activity = nil }
    }
}

/// The Bumblebee app icon, bundled as a resource so it can be reused for the
/// dock icon and in-app logos.
enum AppIcon {
    static let image: NSImage? = Bundle.module.image(forResource: "AppIcon")
}

/// Sets the bundled bee icon as the dock/app icon at runtime, so it shows even
/// when launched outside a fully-assembled .app bundle.
enum DockIcon {
    static func install() {
        if let img = AppIcon.image {
            NSApplication.shared.applicationIconImage = img
        }
    }
}
