import SwiftUI

/// Auto-scaled top-down position trail (X right, Y up), 1 m grid.
struct PositionMapView: View {
    let trail: [CGPoint]

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.bg))
            let pad: CGFloat = 18

            // Bounds (at least ±1 m).
            var minX = -1.0, maxX = 1.0, minY = -1.0, maxY = 1.0
            for p in trail {
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minY = min(minY, p.y); maxY = max(maxY, p.y)
            }
            let spanX = max(maxX - minX, 0.5), spanY = max(maxY - minY, 0.5)
            let span = max(spanX, spanY) * 1.15
            let cxData = (minX + maxX) / 2, cyData = (minY + maxY) / 2
            let plot = min(size.width, size.height) - pad * 2
            let scale = plot / span
            let ox = size.width / 2, oy = size.height / 2

            func toScreen(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: ox + (x - cxData) * scale, y: oy - (y - cyData) * scale)
            }

            // Grid at 1 m steps.
            let half = span / 2
            var g = -ceil(half)
            while g <= ceil(half) {
                let vx = cxData + g, vy = cyData + g
                let sx = toScreen(vx, 0).x, sy = toScreen(0, vy).y
                ctx.stroke(Path { p in p.move(to: CGPoint(x: sx, y: pad)); p.addLine(to: CGPoint(x: sx, y: size.height - pad)) },
                           with: .color(Theme.gridLine), lineWidth: 0.5)
                ctx.stroke(Path { p in p.move(to: CGPoint(x: pad, y: sy)); p.addLine(to: CGPoint(x: size.width - pad, y: sy)) },
                           with: .color(Theme.gridLine), lineWidth: 0.5)
                g += 1
            }

            // Origin axes.
            let o = toScreen(0, 0)
            ctx.stroke(Path { p in p.move(to: CGPoint(x: o.x, y: pad)); p.addLine(to: CGPoint(x: o.x, y: size.height - pad)) },
                       with: .color(Theme.axisLine), lineWidth: 1)
            ctx.stroke(Path { p in p.move(to: CGPoint(x: pad, y: o.y)); p.addLine(to: CGPoint(x: size.width - pad, y: o.y)) },
                       with: .color(Theme.axisLine), lineWidth: 1)

            // Trail with fading alpha.
            if trail.count > 1 {
                for i in 1..<trail.count {
                    let a = Double(i) / Double(trail.count)
                    let p0 = toScreen(trail[i - 1].x, trail[i - 1].y)
                    let p1 = toScreen(trail[i].x, trail[i].y)
                    ctx.stroke(Path { p in p.move(to: p0); p.addLine(to: p1) },
                               with: .color(Theme.primary.opacity(0.2 + 0.8 * a)), lineWidth: 1.5)
                }
            }
            // Current position dot.
            if let last = trail.last {
                let s = toScreen(last.x, last.y)
                ctx.fill(Path(ellipseIn: CGRect(x: s.x - 4, y: s.y - 4, width: 8, height: 8)),
                         with: .color(Theme.caution))
            }
        }
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rMedia))
        .overlay(RoundedRectangle(cornerRadius: Theme.rMedia).stroke(Theme.border, lineWidth: 1))
    }
}
