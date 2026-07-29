import SwiftUI

/// Native MJPEG camera view. Owns an MJPEGStream and rebuilds the URL when the
/// host or topic changes. Supports 180° flip.
struct CameraView: View {
    let host: String
    let topic: String
    var quality = 60
    var fps = 12
    var width = 320
    var height = 240
    @State private var flipped = false
    @StateObject private var stream = MJPEGStream()

    private var streamURL: URL? {
        URL(string: "http://\(host):8080/stream?topic=\(topic)&type=mjpeg&quality=\(quality)&fps=\(fps)&width=\(width)&height=\(height)")
    }

    var body: some View {
        ZStack {
            Color.black
            if let img = stream.image {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fit)
                    .rotationEffect(.degrees(flipped ? 180 : 0))
            } else {
                VStack(spacing: Theme.s2) {
                    ProgressView().controlSize(.small)
                    Text("waiting for video…").font(Theme.monoSmall).foregroundStyle(Theme.muted)
                }
            }
            VStack {
                HStack {
                    Spacer()
                    Button { flipped.toggle() } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderless)
                    .padding(Theme.s1 + 2)
                    .background(Theme.scrim)
                    .clipShape(Circle())
                    .padding(Theme.s1 + 2)
                    .help("Flip 180°")
                }
                Spacer()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.rMedia))
        .onAppear { restart() }
        .onChange(of: host) { _, _ in restart() }
        .onChange(of: topic) { _, _ in restart() }
        .onDisappear { stream.stop() }
    }

    private func restart() {
        guard let url = streamURL else { return }
        stream.start(url: url)
    }
}
