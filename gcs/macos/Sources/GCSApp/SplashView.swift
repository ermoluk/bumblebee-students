import SwiftUI

/// Launch boot screen — a static brand hold shown briefly before the connect
/// screen. No glow, no animation: just the mark and wordmark over the connect
/// palette. The parent (`RootView`) cuts to `LaunchView` after a short delay.
struct SplashView: View {
    var body: some View {
        ZStack {
            ConnectTheme.background.ignoresSafeArea()

            VStack(spacing: 22) {
                if let icon = AppIcon.image {
                    Image(nsImage: icon)
                        .resizable().interpolation(.high)
                        .frame(width: 76, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                VStack(spacing: 7) {
                    (Text("Bumblebee ").foregroundColor(ConnectTheme.text)
                        + Text("GCS").foregroundColor(ConnectTheme.orange))
                        .font(.system(size: 26, weight: .bold)).tracking(-0.3)
                    Text("GROUND CONTROL STATION")
                        .font(.system(size: 11, design: .monospaced)).tracking(2)
                        .foregroundStyle(ConnectTheme.muted)
                }
            }
            .padding(40)
        }
        .foregroundStyle(ConnectTheme.text)
    }
}
