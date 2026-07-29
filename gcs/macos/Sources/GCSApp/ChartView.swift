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

/// Filled line chart of the last N samples with a latest-value label.
struct ChartView: View {
    let title: String
    let data: [Double]
    let color: Color
    var fixedMin: Double? = nil
    var fixedMax: Double? = nil
    var unit: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s1) {
            HStack {
                Text(title).font(Theme.monoSmall).foregroundStyle(Theme.muted)
                Spacer()
                Text(latestLabel).font(Theme.monoSmall).foregroundStyle(color)
            }
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.bg))
                guard data.count > 1 else { return }
                let lo = fixedMin ?? (data.min() ?? 0)
                var hi = fixedMax ?? (data.max() ?? 1)
                if hi - lo < 1e-6 { hi = lo + 1 }
                let n = data.count
                func pt(_ i: Int) -> CGPoint {
                    let x = size.width * CGFloat(i) / CGFloat(n - 1)
                    let norm = (data[i] - lo) / (hi - lo)
                    let y = size.height * (1 - CGFloat(norm))
                    return CGPoint(x: x, y: y)
                }
                var area = Path()
                area.move(to: CGPoint(x: 0, y: size.height))
                for i in 0..<n { area.addLine(to: pt(i)) }
                area.addLine(to: CGPoint(x: size.width, y: size.height))
                area.closeSubpath()
                ctx.fill(area, with: .color(color.opacity(0.15)))

                var line = Path()
                line.move(to: pt(0))
                for i in 1..<n { line.addLine(to: pt(i)) }
                ctx.stroke(line, with: .color(color), lineWidth: 1.5)
            }
            .frame(height: 56)
            .clipShape(RoundedRectangle(cornerRadius: Theme.rSmall))
        }
    }

    private var latestLabel: String {
        guard let v = data.last else { return "—" }
        return String(format: "%.2f", v) + (unit.isEmpty ? "" : " \(unit)")
    }
}
