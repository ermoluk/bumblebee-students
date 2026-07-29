# Bumblebee GCS — Windows

Native Windows port of the macOS `bumblebee_gcs_app` (SwiftUI → WinUI 3).
Design and feature parity: the same dark glass interface, the same screens,
the same drone protocols.

## Stack

- **WinUI 3** (Windows App SDK 1.7), C# / .NET 10, unpackaged + self-contained
- Acrylic (`AcrylicBrush`) instead of `ultraThinMaterial`, Segoe Fluent Icons instead of SF Symbols
- Attitude indicator / charts / position map — XAML shapes with transforms
- `ClientWebSocket` — rosbridge `:9090`; `HttpClient` — MJPEG `:8080`, metrics `:8888`, API `:8765`
- DNS-SD (`DeviceWatcher`, `_bumblebee._tcp`) + subnet scan on `:9090` — drone discovery
- `ManagedNativeWifi` (wlanapi) — air scan and hand-off via the `Bumblebee-*` hotspot
  (Windows 11 requires location services enabled for WiFi scanning)
- `PasswordVault` — WiFi provisioning password; `%LOCALAPPDATA%\BumblebeeGCS\settings.json` — lastHost/fleet

## Build and run

```powershell
# build
dotnet build src\BumblebeeGcs\BumblebeeGcs.csproj -c Release

# run
src\BumblebeeGcs\bin\x64\Release\net10.0-windows10.0.22621.0\win-x64\BumblebeeGcs.exe

# self-contained delivery (publish folder, no SDK needed on the target machine)
dotnet publish src\BumblebeeGcs\BumblebeeGcs.csproj -c Release -r win-x64
```

## Testing without a drone — SimDrone

`tools\SimDrone` emulates a drone on localhost: rosbridge telemetry (circular flight,
battery drain), Raspberry Pi metrics, `/api/*` (LED/sounds/wifi) and a synthetic MJPEG stream.

```powershell
dotnet run --project tools\SimDrone
# then enter the host in the GCS:  localhost
```

Test hook: `BumblebeeGcs.exe --connect localhost` connects right away, skipping the selection screen.

## Structure

```
src\BumblebeeGcs\
  Theme\      Palette/ConnectPalette (colors 1:1 with mac), Fonts, IconGlyphs, UI factories
  Models\     TelemetryStore, SystemMetrics, KnownDrone, QuatToEuler
  Services\   RosbridgeClient, MjpegStream, MetricsClient, DroneApi,
              DroneScanner (+DnssdBrowser), WifiHandoff, AppSettings,
              CredentialStore, KeepAwake, AppState
  Controls\   PanelCard, StatTile, StatusDot, LabeledBar, chips/bars/fields,
              AttitudeView, ChartView, PositionMapView, CameraView, AdaptiveGridPanel
  Views\      Splash, Launch, ProvisioningDialog, MainShell, Dashboard,
              Entertainment, Settings
tools\SimDrone\   drone mock for end-to-end testing
```

Hotkeys: `Ctrl+R` Reconnect · `Ctrl+K` Rescan · `Ctrl+Shift+D` Disconnect.
