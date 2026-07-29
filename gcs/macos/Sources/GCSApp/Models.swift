import SwiftUI

// MARK: - Theme (parity with the web dashboard)

enum Theme {
    // Surfaces
    static let bg            = Color(hex: 0x0a0c10)
    static let bgDeep        = Color(hex: 0x10141d)   // 4th shade, base of the app gradient
    static let surface       = Color(hex: 0x111318)
    static let surfaceRaised = Color(hex: 0x161a22)
    static let border        = Color(hex: 0x232a39)
    static let hairline      = Color(hex: 0x1a2030)

    /// Canonical app background — every screen uses this for a uniform glass base.
    static let appGradient = LinearGradient(colors: [bg, bgDeep], startPoint: .top, endPoint: .bottom)

    // Accents / status
    static let accent   = Color(hex: 0xf5c842)
    static let accent2  = Color(hex: 0x3b82f6)
    static let ok       = Color(hex: 0x22c55e)
    static let warn     = Color(hex: 0xf97316)
    static let danger   = Color(hex: 0xef4444)
    static let text     = Color(hex: 0xe2e8f0)
    static let muted    = Color(hex: 0x64748b)

    // Accent semantics — read call sites by role, not by hue.
    static let primary  = accent2   // interactive: buttons, links, selection, focus
    static let caution  = accent    // aviation-amber: caution / important status only
    static let selectionBg = accent2.opacity(0.18)   // nav rows, selected chips
    static let hoverBg     = accent2.opacity(0.10)   // hover affordance

    // Categorical data palette — neutral series colors for charts/bars.
    static let dataBlue   = accent2
    static let dataTeal   = Color(hex: 0x06b6d4)
    static let dataGreen  = ok
    static let dataOrange = warn

    // Spacing scale
    static let s0: CGFloat = 2
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 24
    static let s6: CGFloat = 32
    static let s7: CGFloat = 40

    // Corner radii
    static let rSmall: CGFloat = 4
    static let rMedia: CGFloat = 6
    static let rControl: CGFloat = 8
    static let rPanel: CGFloat = 10
    static let rLogo: CGFloat = 18

    // SF Symbol icon sizes
    static let iconSm: CGFloat = 11
    static let iconMd: CGFloat = 15
    static let iconLg: CGFloat = 18
    static let iconXl: CGFloat = 22

    // Typography — SF Pro for chrome, SF Mono for telemetry values.
    static let title      = Font.system(size: 15, weight: .semibold)
    static let label      = Font.system(size: 11, weight: .medium)
    static let sectionLbl = Font.system(size: 10, weight: .semibold, design: .default)
    static let value      = Font.system(.body, design: .monospaced)
    static let valueBig   = Font.system(size: 22, weight: .semibold, design: .monospaced)
    static let mono       = Font.system(.body, design: .monospaced)
    static let monoSmall  = Font.system(.caption, design: .monospaced)
    // Chrome / text scale
    static let brand      = Font.system(size: 14, weight: .bold)
    static let logoTitle  = Font.system(size: 24, weight: .bold)
    static let body       = Font.system(size: 13, weight: .regular)
    static let bodyStrong = Font.system(size: 13, weight: .semibold)
    static let bodyMed    = Font.system(size: 12, weight: .medium)
    static let button     = Font.system(size: 13, weight: .semibold)
    static let buttonSm   = Font.system(size: 12, weight: .medium)
    static let chip       = Font.system(size: 11, weight: .medium)
    // Mono / telemetry scale
    static let statValue  = Font.system(size: 17, weight: .semibold, design: .monospaced)
    static let hostMono   = Font.system(size: 12, weight: .semibold, design: .monospaced)
    static let logMono    = Font.system(size: 10, design: .monospaced)
    static let badge      = Font.system(size: 10, weight: .bold, design: .monospaced)
    static let micro      = Font.system(size: 8, design: .monospaced)

    // Opacity / glass tokens
    static let edgeHi      = Color.white.opacity(0.22)   // glass edge highlight (top)
    static let edgeLo      = Color.white.opacity(0.04)   // glass edge highlight (bottom)
    static let ghostStroke = Color.white.opacity(0.10)   // ghost button border
    static let fillFaint   = Color.white.opacity(0.06)   // unselected chip fill
    static let scrim       = Color.black.opacity(0.4)    // overlay button backdrop
    static let gridLine    = Color(hex: 0x232a39).opacity(0.5)   // map grid (border @ 0.5)
    static let axisLine    = Color(hex: 0x64748b).opacity(0.6)   // map axes (muted @ 0.6)

    // Elevation
    static let shadowColor: Color = .black.opacity(0.3)
    static let shadowRadius: CGFloat = 8
    static let shadowY: CGFloat = 3
}

// MARK: - Connect / Splash palette (scoped to the startup screens only)
//
// Adapted from the "Bumblebee Connect" design: a warmer radial-glow backdrop with
// an orange brand accent and a blue action color. Kept separate from `Theme` so the
// rest of the app (dashboard, settings, etc.) stays on the amber cockpit palette.
enum ConnectTheme {
    static let bg        = Color(hex: 0x0b0d12)   // page base
    static let bgGlow    = Color(hex: 0x131722)   // radial glow center
    static let text      = Color(hex: 0xe6ebf2)
    static let orange    = Color(hex: 0xff9d1a)   // brand accent (logo, last-drone)
    static let blue      = Color(hex: 0x2f81f7)   // primary action (scan / connect)
    static let blueHover = Color(hex: 0x4c92ff)
    static let blueSoft  = Color(hex: 0x7fb0ff)   // outline-button text
    static let green     = Color(hex: 0x35d07f)   // reachable / linked
    static let muted     = Color(hex: 0x7c8494)
    static let muted2    = Color(hex: 0x8b93a2)
    static let faint     = Color(hex: 0x535b6a)   // placeholders, dividers, "IP" label
    static let hairline  = Color.white.opacity(0.08)
    static let rowBg     = Color.white.opacity(0.02)

    /// radial-gradient(130% 100% at 50% -10%, #131722 0%, #0b0d12 60%)
    static let background = RadialGradient(
        gradient: Gradient(stops: [
            .init(color: bgGlow, location: 0),
            .init(color: bg, location: 0.6),
        ]),
        center: UnitPoint(x: 0.5, y: -0.1),
        startRadius: 0, endRadius: 760)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: 1)
    }
}

// MARK: - Math helpers

struct Euler { var roll: Double; var pitch: Double; var yaw: Double } // degrees

func quatToEuler(_ x: Double, _ y: Double, _ z: Double, _ w: Double) -> Euler {
    let roll  = atan2(2 * (w * x + y * z), 1 - 2 * (x * x + y * y))
    let sp    = max(-1, min(1, 2 * (w * y - z * x)))
    let pitch = asin(sp)
    let yaw   = atan2(2 * (w * z + x * y), 1 - 2 * (y * y + z * z))
    let r = 180.0 / Double.pi
    return Euler(roll: roll * r, pitch: pitch * r, yaw: yaw * r)
}

// MARK: - System metrics (:8888 JSON)

struct SystemMetrics: Equatable {
    var cpuTemp: Double?
    var cpuPct: Double?
    var load1: Double?
    var load5: Double?
    var load15: Double?
    var cpuCount: Int?
    var memUsed: Int?
    var memTotal: Int?
    var memPct: Double?
}

// MARK: - Log + alerts

struct LogEntry: Identifiable {
    let id = UUID()
    let time: String
    let text: String
}

// MARK: - Telemetry store (fed by RosbridgeClient on the main thread)

final class TelemetryStore: ObservableObject {
    // Connection / state
    @Published var rosConnected = false
    @Published var mode = "—"
    @Published var armed = false

    // Battery
    @Published var batteryVoltage: Double?
    @Published var batteryPct: Double?

    // Pose
    @Published var posX = 0.0
    @Published var posY = 0.0
    @Published var posZ = 0.0
    @Published var roll = 0.0
    @Published var pitch = 0.0
    @Published var yaw = 0.0

    // Velocity
    @Published var vx = 0.0
    @Published var vy = 0.0
    @Published var vz = 0.0
    var speedH: Double { (vx * vx + vy * vy).squareRoot() }
    var speedV: Double { abs(vz) }

    // IMU
    @Published var gyroMag = 0.0   // deg/s
    @Published var accelMag = 0.0  // m/s²

    // Trails / charts
    @Published var posTrail: [CGPoint] = []
    @Published var chartAlt: [Double] = []
    @Published var chartSpd: [Double] = []
    @Published var chartBat: [Double] = []

    @Published var logs: [LogEntry] = []
    @Published var lastUpdate = "—"

    private let posMax = 200
    private let chartMax = 120

    func touched() { lastUpdate = Self.timeString() }

    func log(_ msg: String) {
        logs.insert(LogEntry(time: Self.timeString(), text: msg), at: 0)
        if logs.count > 20 { logs.removeLast(logs.count - 20) }
    }

    func pushTrail(_ x: Double, _ y: Double) {
        posTrail.append(CGPoint(x: x, y: y))
        if posTrail.count > posMax { posTrail.removeFirst(posTrail.count - posMax) }
    }

    func pushChart(_ kp: ReferenceWritableKeyPath<TelemetryStore, [Double]>, _ v: Double) {
        self[keyPath: kp].append(v)
        let arr = self[keyPath: kp]
        if arr.count > chartMax { self[keyPath: kp].removeFirst(arr.count - chartMax) }
    }

    func resetForReconnect() {
        rosConnected = false
        mode = "—"; armed = false
        batteryVoltage = nil; batteryPct = nil
    }

    static func timeString() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}
