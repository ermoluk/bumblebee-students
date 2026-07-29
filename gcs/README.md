# 🎛️ Ground Control Station — Source Code

Source code of the Bumblebee GCS desktop apps. Ready-to-run builds are on the download links — see [Ground Control Station](https://github.com/futureLabKezad/bumblebee-students/wiki/Ground‐Control‐Station) in the wiki.

| Folder | Platform | Stack | Build |
| --- | --- | --- | --- |
| `macos/` | macOS 14+ (Apple Silicon) | Swift 5.9 / SwiftUI | `./build_app.sh` → `build/Bumblebee GCS.app` |
| `windows/` | Windows 10/11 x64 | C# / .NET 10 / WinUI 3 | `dotnet build src\BumblebeeGcs\BumblebeeGcs.csproj -c Release` |

`windows/tools/SimDrone` is a mock drone on localhost for testing the GCS without hardware (`dotnet run --project tools\SimDrone`, then connect to `localhost`).
