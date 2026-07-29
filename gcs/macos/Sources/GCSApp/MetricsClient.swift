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

import Foundation

/// Polls the drone's system-metrics endpoint (http://host:8888/) every 2 s.
final class MetricsClient: ObservableObject {
    @Published var metrics = SystemMetrics()

    private var timer: Timer?
    private var host = ""
    private let session = URLSession(configuration: .ephemeral)

    func start(host: String) {
        stop()
        self.host = host
        fetch()
        let t = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in self?.fetch() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func fetch() {
        guard let url = URL(string: "http://\(host):8888/") else { return }
        var req = URLRequest(url: url, timeoutInterval: 2.0)
        req.httpMethod = "GET"
        session.dataTask(with: req) { [weak self] data, _, _ in
            guard let self = self, let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            var m = SystemMetrics()
            m.cpuTemp = obj["cpu_temp"] as? Double
            m.cpuPct = obj["cpu_pct"] as? Double
            m.load1 = obj["load1"] as? Double
            m.load5 = obj["load5"] as? Double
            m.load15 = obj["load15"] as? Double
            m.cpuCount = obj["cpu_count"] as? Int
            m.memUsed = obj["mem_used"] as? Int
            m.memTotal = obj["mem_total"] as? Int
            m.memPct = obj["mem_pct"] as? Double
            DispatchQueue.main.async { self.metrics = m }
        }.resume()
    }
}
