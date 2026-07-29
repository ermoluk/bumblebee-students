import SwiftUI
import AppKit

/// Native MJPEG (`multipart/x-mixed-replace`) client. Streams from
/// `http://host:8080/stream?...`, splits the byte stream on JPEG SOI/EOI
/// markers, decodes each frame to an NSImage and publishes the latest one.
/// No WebView involved — the video is rendered fully natively.
final class MJPEGStream: NSObject, ObservableObject, URLSessionDataDelegate {
    @Published var image: NSImage?
    @Published var receiving = false

    private var session: URLSession?
    private var dataTask: URLSessionDataTask?
    private var buffer = Data()
    private let decodeQueue = DispatchQueue(label: "gcs.mjpeg.decode")

    // JPEG markers.
    private let soi: [UInt8] = [0xFF, 0xD8]
    private let eoi: [UInt8] = [0xFF, 0xD9]

    private var currentURL: URL?

    func start(url: URL) {
        if url == currentURL, dataTask != nil { return }
        stop()
        currentURL = url
        buffer.removeAll(keepingCapacity: true)
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = .infinity
        let s = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        session = s
        let t = s.dataTask(with: url)
        dataTask = t
        t.resume()
    }

    func stop() {
        dataTask?.cancel()
        dataTask = nil
        session?.invalidateAndCancel()
        session = nil
        currentURL = nil
        DispatchQueue.main.async { self.receiving = false }
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive data: Data) {
        decodeQueue.async {
            self.buffer.append(data)
            self.extractFrames()
            // Guard against unbounded growth if no full frame appears.
            if self.buffer.count > 4 * 1024 * 1024 {
                self.buffer.removeAll(keepingCapacity: true)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        DispatchQueue.main.async { self.receiving = false }
        // Auto-retry the same URL after a short delay (server restart / wifi blip).
        guard let url = currentURL else { return }
        decodeQueue.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self = self, self.currentURL == url, self.dataTask == nil else { return }
            self.start(url: url)
        }
        dataTask = nil
        session.invalidateAndCancel()
        self.session = nil
    }

    // MARK: - Frame extraction

    private func extractFrames() {
        // Consume every complete JPEG in the buffer but keep only the LAST one,
        // then decode it once. If frames arrive in a burst (wifi jitter, a
        // higher fps than the UI redraws), decoding only the freshest frame
        // keeps latency low and avoids wasting CPU on frames that would be
        // immediately overwritten on screen.
        var lastFrame: Data?
        while true {
            guard let start = buffer.firstRange(of: Data(soi)) else { break }
            guard let endRange = buffer.range(of: Data(eoi),
                                              in: start.upperBound..<buffer.endIndex) else {
                // No complete frame yet; drop any garbage before SOI.
                if start.lowerBound > buffer.startIndex {
                    buffer.removeSubrange(buffer.startIndex..<start.lowerBound)
                }
                break
            }
            lastFrame = buffer.subdata(in: start.lowerBound..<endRange.upperBound)
            buffer.removeSubrange(buffer.startIndex..<endRange.upperBound)
        }
        if let frameData = lastFrame, let img = NSImage(data: frameData) {
            DispatchQueue.main.async {
                self.image = img
                self.receiving = true
            }
        }
    }
}

private extension Data {
    /// First range of `sub` searching the whole data.
    func firstRange(of sub: Data) -> Range<Index>? {
        range(of: sub)
    }
}
