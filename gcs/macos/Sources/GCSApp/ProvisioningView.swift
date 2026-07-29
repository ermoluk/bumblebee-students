import SwiftUI
import AppKit

/// One-tap drone setup over its WiFi hotspot. Shows the Mac's current network
/// (auto-filled) + a password field (typed once, remembered in the app's own
/// keychain), scans the air for `Bumblebee-*` setup hotspots, and on selection
/// runs the full hand-off with a live loading state until the drone is back
/// online and connected.
struct ProvisioningView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var handoff: WifiHandoff
    @Environment(\.dismiss) private var dismiss

    @State private var targetPassword = ""

    var body: some View {
        ZStack {
            ConnectTheme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 20) {
                header
                Divider().overlay(ConnectTheme.hairline)
                content
                Spacer(minLength: 0)
            }
            .padding(28)
        }
        .frame(width: 560, height: 560)
        .foregroundStyle(ConnectTheme.text)
        .onAppear {
            handoff.refreshCurrentSSID()
            targetPassword = AppKeychain.password(for: handoff.currentSSID) ?? ""
            Task { await handoff.scanHotspots() }
        }
        .onChange(of: doneHost) { _, host in
            if let host { app.connect(to: host); dismiss() }
        }
    }

    // MARK: - Derived phase helpers

    private var doneHost: String? { if case let .done(h) = handoff.phase { return h }; return nil }
    private var failedMsg: String? { if case let .failed(m) = handoff.phase { return m }; return nil }

    private var canProvision: Bool {
        !handoff.currentSSID.isEmpty && !targetPassword.isEmpty && !handoff.phase.isBusy
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Set up a drone").font(.system(size: 20, weight: .bold))
                Text("Over its WiFi hotspot — no cables, no router")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(ConnectTheme.muted)
            }
            Spacer()
            Button("Close") { handoff.reset(); dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(ConnectTheme.muted)
                .disabled(handoff.phase.isBusy)
        }
    }

    // MARK: - Content by phase

    @ViewBuilder private var content: some View {
        if handoff.phase.isBusy {
            busyView
        } else if handoff.phase == .needLocationPermission {
            permissionView
        } else {
            formView
        }
    }

    // Loading window shown throughout join → push → wait.
    private var busyView: some View {
        VStack(spacing: 18) {
            Spacer()
            ProgressView().controlSize(.large)
            Text(busyText)
                .font(.system(size: 14, weight: .semibold))
                .multilineTextAlignment(.center)
            Text("Keep this window open — the Mac will switch networks and come back on its own.")
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(ConnectTheme.muted)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var busyText: String {
        switch handoff.phase {
        case .scanning: return "Scanning the air for drone hotspots…"
        case .joiningHotspot(let s): return "Joining \(s)…"
        case .pushingCreds: return "Sending your WiFi to the drone…"
        case .waitingForDrone: return "Waiting for the drone to join \(handoff.currentSSID) and come online…"
        default: return "Working…"
        }
    }

    private var permissionView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "location.slash").font(.system(size: 34)).foregroundStyle(ConnectTheme.orange)
            Text("Location access needed").font(.system(size: 15, weight: .semibold))
            Text(handoff.locationBlocked
                 ? "macOS blocked Location for this app, so it can't read nearby WiFi. Enable it in System Settings ▸ Privacy & Security ▸ Location Services, then Rescan."
                 : "macOS needs Location permission to read nearby WiFi. Approve the prompt — if none appears, open System Settings.")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(ConnectTheme.muted)
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button("Open System Settings") { openLocationSettings() }
                    .buttonStyle(.plain).foregroundStyle(ConnectTheme.orange)
                Button("Rescan") { handoff.requestLocation(); Task { await handoff.scanHotspots() } }
                    .buttonStyle(.plain).foregroundStyle(ConnectTheme.blueSoft)
            }
            .font(.system(size: 13, weight: .semibold)).padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onAppear { handoff.requestLocation() }   // fire the system prompt on entry
    }

    private func openLocationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

    private var formView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Target network (auto) + password (typed once).
            VStack(alignment: .leading, spacing: 8) {
                labeled("YOUR WIFI", handoff.currentSSID.isEmpty ? "— not connected —" : handoff.currentSSID)
                HStack(spacing: 8) {
                    Text("PWD").font(.system(size: 11, design: .monospaced)).tracking(1.3)
                        .foregroundStyle(ConnectTheme.faint).frame(width: 42, alignment: .leading)
                    SecureField("WiFi password", text: $targetPassword)
                        .textFieldStyle(.plain).font(.system(size: 14, design: .monospaced))
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(ConnectTheme.rowBg)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(ConnectTheme.hairline, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                Text("The drone will join this network. Entered once, remembered on this Mac.")
                    .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(ConnectTheme.faint)
            }

            if let failedMsg {
                Text(failedMsg).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ConnectTheme.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Hotspot list.
            HStack {
                Text("DRONE HOTSPOTS").font(.system(size: 11, design: .monospaced)).tracking(1.2)
                    .foregroundStyle(ConnectTheme.faint)
                Spacer()
                Button("Rescan") { Task { await handoff.scanHotspots() } }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ConnectTheme.blueSoft)
            }

            if handoff.hotspots.isEmpty {
                Text("No drone hotspots nearby. Power on a drone with no known WiFi — it raises a Bumblebee-XXXX hotspot — then Rescan.")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(ConnectTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(handoff.hotspots) { h in hotspotRow(h) }
                    }
                }
                .frame(maxHeight: 190)
            }
        }
    }

    private func hotspotRow(_ h: WifiHandoff.Hotspot) -> some View {
        Button {
            AppKeychain.setPassword(targetPassword, for: handoff.currentSSID)
            Task {
                await handoff.provision(hotspotSSID: h.ssid,
                                        targetSSID: handoff.currentSSID,
                                        targetPassword: targetPassword,
                                        onDrone: { _ in })
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "wifi").foregroundStyle(ConnectTheme.orange)
                Text(h.ssid).font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(h.rssi) dBm").font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ConnectTheme.muted2)
                Text("Set up →").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(canProvision ? ConnectTheme.orange : ConnectTheme.faint)
            }
            .padding(.vertical, 12).padding(.horizontal, 14)
            .background(ConnectTheme.rowBg)
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(ConnectTheme.hairline, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canProvision)
    }

    private func labeled(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 11, design: .monospaced)).tracking(1.3)
                .foregroundStyle(ConnectTheme.faint).frame(width: 72, alignment: .leading)
            Text(value).font(.system(size: 14, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(ConnectTheme.rowBg)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ConnectTheme.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
