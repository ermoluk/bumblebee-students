import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var t: TelemetryStore
    @EnvironmentObject var metricsClient: MetricsClient

    @State private var bottomTopic = "/main_camera/image_raw"
    @State private var pipBig = false

    private let bottomTabs: [(String, String)] = [
        ("Bottom", "/main_camera/image_raw"),
        ("ArUco", "/aruco_detect/debug"),
    ]

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: Theme.s4) {
                    heroRow
                    cameras
                    masonry(width: geo.size.width)
                }
                .padding(Theme.s4)
            }
            .background(Theme.appGradient)
        }
    }

    /// Packs panels into tight columns (Pinterest-style) so short panels don't
    /// leave big gaps the way a row-aligned grid does.
    private func masonry(width: CGFloat) -> some View {
        let cols = width > 1500 ? 3 : (width > 1040 ? 2 : 1)
        let panels: [AnyView] = [
            AnyView(attitudePanel), AnyView(telemetryPanel), AnyView(flightDataPanel),
            AnyView(systemPanel), AnyView(chartsPanel), AnyView(mapPanel), AnyView(logPanel),
        ]
        var columns = Array(repeating: [AnyView](), count: cols)
        for (i, p) in panels.enumerated() { columns[i % cols].append(p) }
        return HStack(alignment: .top, spacing: Theme.s4) {
            ForEach(0..<cols, id: \.self) { c in
                VStack(spacing: Theme.s4) {
                    ForEach(0..<columns[c].count, id: \.self) { j in columns[c][j] }
                }
            }
        }
    }

    // MARK: - Hero

    private var heroRow: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: Theme.s3)], spacing: Theme.s3) {
            StatTile(label: "Mode", value: t.mode.uppercased(), icon: "airplane", color: Theme.primary)
            StatTile(label: "State", value: t.armed ? "ARMED" : "DISARMED",
                     icon: t.armed ? "bolt.fill" : "bolt.slash", color: t.armed ? Theme.danger : Theme.muted)
            StatTile(label: "Battery", value: batteryShort, icon: "battery.75", color: batteryColor)
            StatTile(label: "Altitude", value: String(format: "%.2f m", t.posZ), icon: "arrow.up.to.line", color: Theme.primary)
            StatTile(label: "Link", value: t.rosConnected ? "OK" : "—",
                     icon: "dot.radiowaves.up.forward", color: t.rosConnected ? Theme.ok : Theme.warn)
        }
    }

    // MARK: - Cameras

    private var cameras: some View {
        HStack(alignment: .top, spacing: Theme.s4) {
            cameraCard(title: "Front", tabs: nil) {
                CameraView(host: app.droneHost, topic: "/second_camera/image_raw")
                    .aspectRatio(4.0/3.0, contentMode: .fit)
            }
            cameraCard(title: "Bottom", tabs: AnyView(tabBar)) {
                ZStack(alignment: .topTrailing) {
                    CameraView(host: app.droneHost, topic: bottomTopic)
                        .aspectRatio(4.0/3.0, contentMode: .fit)
                    CameraView(host: app.droneHost, topic: "/aruco_map/image",
                               quality: 50, fps: 3, width: 160, height: 120)
                        .frame(width: pipBig ? 190 : 120, height: pipBig ? 142 : 90)
                        .overlay(RoundedRectangle(cornerRadius: Theme.rMedia).stroke(Theme.primary.opacity(0.7), lineWidth: 1))
                        .padding(Theme.s2)
                        .onTapGesture { pipBig.toggle() }
                }
            }
        }
    }

    private var tabBar: some View {
        SegmentedTabs(options: bottomTabs.map { (label: $0.0, value: $0.1) }, selection: $bottomTopic)
    }

    private func cameraCard<V: View>(title: String, tabs: AnyView?, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            HStack {
                Text(title.uppercased()).font(Theme.sectionLbl).tracking(1.1).foregroundStyle(Theme.muted)
                Spacer()
                if let tabs { tabs }
            }
            content()
                .frame(maxWidth: .infinity)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: Theme.rMedia))
        }
        .padding(Theme.s3)
        .frame(maxWidth: .infinity)
        .glassCard(Theme.rPanel)
    }

    // MARK: - Panels

    private var attitudePanel: some View {
        Panel(title: "Attitude", icon: "gyroscope") {
            HStack { Spacer(); AttitudeView(roll: t.roll, pitch: t.pitch); Spacer() }
            HStack {
                Readout(label: "Roll", value: String(format: "%.1f°", t.roll))
                Readout(label: "Pitch", value: String(format: "%.1f°", t.pitch))
                Readout(label: "Yaw", value: String(format: "%.1f°", t.yaw))
            }
        }
    }

    private var telemetryPanel: some View {
        Panel(title: "Telemetry", icon: "location.fill") {
            LabeledBar(label: "Battery", value: batteryText, pct: t.batteryPct ?? 0, color: batteryColor)
            Readout(label: "X", value: String(format: "%+.3f", t.posX), color: Theme.danger)
            Readout(label: "Y", value: String(format: "%+.3f", t.posY), color: Theme.ok)
            Readout(label: "Z", value: String(format: "%+.3f", t.posZ), color: Theme.accent2)
            Divider().overlay(Theme.hairline)
            Readout(label: "Vx", value: String(format: "%+.3f", t.vx))
            Readout(label: "Vy", value: String(format: "%+.3f", t.vy))
            Readout(label: "Vz", value: String(format: "%+.3f", t.vz))
        }
    }

    private var flightDataPanel: some View {
        Panel(title: "Flight Data", icon: "speedometer") {
            LabeledBar(label: "Horiz. Speed", value: String(format: "%.2f m/s", t.speedH), pct: pctOf(t.speedH, 5), color: Theme.dataTeal)
            LabeledBar(label: "Vert. Speed", value: String(format: "%.2f m/s", t.speedV), pct: pctOf(t.speedV, 3), color: Theme.dataBlue)
            LabeledBar(label: "Angular Rate", value: String(format: "%.1f °/s", t.gyroMag), pct: pctOf(t.gyroMag, 360), color: Theme.dataOrange)
            LabeledBar(label: "IMU Accel", value: String(format: "%.2f m/s²", t.accelMag), pct: pctOf(t.accelMag, 30), color: Theme.dataGreen)
        }
    }

    private var systemPanel: some View {
        let m = metricsClient.metrics
        return Panel(title: "Raspberry Pi", icon: "cpu") {
            LabeledBar(label: "CPU Temp", value: m.cpuTemp.map { String(format: "%.1f °C", $0) } ?? "—",
                       pct: min(100, m.cpuTemp ?? 0), color: tempColor(m.cpuTemp))
            LabeledBar(label: "CPU Load", value: m.cpuPct.map { String(format: "%.0f%%", $0) } ?? "—",
                       pct: m.cpuPct ?? 0, color: cpuColor(m.cpuPct))
            LabeledBar(label: "Load 1/5/15", value: loadText(m),
                       pct: (m.load1 ?? 0) / Double(m.cpuCount ?? 4) * 100, color: Theme.accent2)
            LabeledBar(label: "RAM", value: memText(m), pct: m.memPct ?? 0, color: Theme.accent2)
        }
    }

    private var chartsPanel: some View {
        Panel(title: "Charts", icon: "chart.xyaxis.line") {
            ChartView(title: "Altitude (m)", data: t.chartAlt, color: Theme.dataBlue)
            ChartView(title: "Speed (m/s)", data: t.chartSpd, color: Theme.dataTeal, fixedMin: 0, fixedMax: 5)
            ChartView(title: "Battery (%)", data: t.chartBat, color: Theme.dataGreen, fixedMin: 0, fixedMax: 100)
        }
    }

    private var mapPanel: some View {
        Panel(title: "Position Map", icon: "map") { PositionMapView(trail: t.posTrail) }
    }

    private var logPanel: some View {
        Panel(title: "Messages", icon: "list.bullet.rectangle") {
            VStack(alignment: .leading, spacing: Theme.s0) {
                if t.logs.isEmpty { Text("—").font(Theme.monoSmall).foregroundStyle(Theme.muted) }
                ForEach(t.logs) { e in
                    HStack(alignment: .top, spacing: Theme.s1 + 2) {
                        Text(e.time).font(Theme.logMono).foregroundStyle(Theme.muted)
                        Text(e.text).font(Theme.logMono).foregroundStyle(Theme.text)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Derived

    private var batteryShort: String { t.batteryPct.map { String(format: "%.0f%%", $0) } ?? "—" }
    private var batteryText: String {
        let v = t.batteryVoltage.map { String(format: "%.2f V", $0) } ?? "— V"
        let p = t.batteryPct.map { String(format: "%.0f%%", $0) } ?? "—"
        return "\(v) · \(p)"
    }
    private var batteryColor: Color {
        guard let p = t.batteryPct else { return Theme.muted }
        return p > 55 ? Theme.ok : (p > 25 ? Theme.warn : Theme.danger)
    }
    private func tempColor(_ x: Double?) -> Color { x.map { $0 < 60 ? Theme.ok : ($0 < 75 ? Theme.warn : Theme.danger) } ?? Theme.muted }
    private func cpuColor(_ x: Double?) -> Color { x.map { $0 < 60 ? Theme.ok : ($0 < 85 ? Theme.warn : Theme.danger) } ?? Theme.muted }
    private func loadText(_ m: SystemMetrics) -> String {
        guard let l1 = m.load1, let l5 = m.load5, let l15 = m.load15 else { return "—" }
        return String(format: "%.2f / %.2f / %.2f", l1, l5, l15)
    }
    private func memText(_ m: SystemMetrics) -> String {
        guard let u = m.memUsed, let tot = m.memTotal, let p = m.memPct else { return "—" }
        return "\(u) / \(tot) MB (\(String(format: "%.0f", p))%)"
    }
}
