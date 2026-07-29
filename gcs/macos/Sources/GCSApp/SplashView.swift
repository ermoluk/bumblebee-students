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
