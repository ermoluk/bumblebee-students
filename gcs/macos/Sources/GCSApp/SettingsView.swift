// Copyright 2026 FutureLab
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppState

    @State private var status: DroneAPI.WifiStatus?

    @State private var scanResults: [DroneAPI.ScanNet] = []
    @State private var scanning = false
    @State private var saved: [String] = []

    @State private var addSSID = ""
    @State private var addPass = ""
    @State private var msg = ""
    @State private var confirmMode: String?

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.s3) {
                statusPanel
                scanPanel
                savedPanel
                addPanel
                if !msg.isEmpty {
                    StatusBanner(text: msg, kind: msg.hasPrefix("error") ? .error : .success)
                }
            }
            .padding(Theme.s4)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.appGradient)
        .task { await refreshStatusLoop() }
        .task { saved = (try? await app.api.savedNetworks()) ?? [] }
    }

    // MARK: - Panels

    private var statusPanel: some View {
        Panel(title: "WiFi Status", icon: "wifi") {
            if let s = status {
                Readout(label: "Mode", value: s.mode.uppercased(),
                        color: s.mode == "client" ? Theme.ok : Theme.warn)
                Readout(label: "Network", value: s.ssid)
                Readout(label: "IP", value: s.ip)
                LabeledBar(label: "Signal", value: "\(s.signal)%", pct: Double(s.signal),
                           color: s.signal > 60 ? Theme.ok : (s.signal > 30 ? Theme.warn : Theme.danger))
                HStack {
                    Button { run { status = try await app.api.wifiStatus() } }
                        label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        .buttonStyle(GhostButtonStyle())
                    Button("Switch Mode") { confirmMode = (s.mode == "client") ? "hotspot" : "client" }
                        .buttonStyle(AccentButtonStyle())
                    Spacer()
                }
            } else {
                Text("loading…").font(Theme.monoSmall).foregroundStyle(Theme.muted)
            }
        }
        .confirmationDialog("Switch WiFi mode?", isPresented: Binding(
            get: { confirmMode != nil }, set: { if !$0 { confirmMode = nil } })) {
            Button("Switch to \(confirmMode ?? "")", role: .destructive) {
                if let m = confirmMode { run { try await app.api.wifiSetMode(m)
                    msg = "switching to \(m)…" } }
                confirmMode = nil
            }
            Button("Cancel", role: .cancel) { confirmMode = nil }
        } message: {
            Text(confirmMode == "hotspot"
                 ? "The drone will broadcast its own hotspot; this Mac will disconnect."
                 : "The hotspot drops and the drone reconnects to wifi (~60 s).")
        }
    }

    private var scanPanel: some View {
        Panel(title: "Available Networks", icon: "antenna.radiowaves.left.and.right") {
            HStack {
                Button { doScan() } label: {
                    if scanning { ProgressView().controlSize(.small) } else { Text("Scan") }
                }.buttonStyle(GhostButtonStyle()).disabled(scanning)
                Spacer()
            }
            ForEach(scanResults) { n in
                HStack(spacing: Theme.s2) {
                    Circle().fill(n.inUse ? Theme.ok : Theme.muted).frame(width: 7, height: 7)
                    Text(n.ssid).font(Theme.monoSmall)
                    Spacer()
                    Text("\(n.signal)%").font(Theme.monoSmall)
                        .foregroundStyle(n.signal > 60 ? Theme.ok : (n.signal > 30 ? Theme.warn : Theme.danger))
                    Badge(text: n.band + "G", color: bandColor(n.band))
                    Button("Connect") { addSSID = n.ssid }
                }
            }
        }
    }

    private var savedPanel: some View {
        Panel(title: "Saved Networks", icon: "bookmark.fill") {
            if saved.isEmpty { Text("none").font(Theme.monoSmall).foregroundStyle(Theme.muted) }
            ForEach(saved, id: \.self) { name in
                HStack {
                    Text(name).font(Theme.monoSmall)
                    Spacer()
                    Button("Remove", role: .destructive) {
                        run { try await app.api.removeNetwork(name); saved = try await app.api.savedNetworks() }
                    }
                }
            }
        }
    }

    private var addPanel: some View {
        Panel(title: "Add / Update Network", icon: "plus.circle") {
            GlassTextField(placeholder: "SSID", text: $addSSID, icon: "wifi")
            GlassTextField(placeholder: "Password", text: $addPass, icon: "key", secure: true)
            HStack {
                Button("Save + Apply Now") {
                    run { try await app.api.saveNetwork(ssid: addSSID, password: addPass)
                          try await app.api.applyNow(ssid: addSSID); msg = "applying \(addSSID)…"
                          try? await Task.sleep(nanoseconds: 5_000_000_000)
                          status = try await app.api.wifiStatus() }
                }.buttonStyle(AccentButtonStyle()).disabled(addSSID.isEmpty)
                Button("Save for next boot") {
                    run { try await app.api.saveNetwork(ssid: addSSID, password: addPass)
                          try await app.api.applyBoot(ssid: addSSID); msg = "saved \(addSSID) for boot" }
                }.buttonStyle(GhostButtonStyle()).disabled(addSSID.isEmpty)
                Spacer()
            }
        }
    }

    // MARK: - Actions

    private func doScan() {
        scanning = true
        run { scanResults = try await app.api.wifiScan(); scanning = false }
    }
    private func refreshStatusLoop() async {
        while !Task.isCancelled {
            status = try? await app.api.wifiStatus()
            try? await Task.sleep(nanoseconds: 15_000_000_000)
        }
    }
    private func bandColor(_ b: String) -> Color {
        b == "5" ? Theme.ok : (b == "6" ? Theme.accent2 : Theme.warn)
    }
    private func run(_ op: @escaping () async throws -> Void) {
        Task { do { try await op() } catch { msg = "error: \(error.localizedDescription)" } }
    }
}
