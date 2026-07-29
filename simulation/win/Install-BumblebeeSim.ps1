# Copyright 2026 FutureLab
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

﻿<#
.SYNOPSIS
    Bumblebee sim installer for Windows 11 (WSL2 + WSLg) -- hardened, unattended.

.DESCRIPTION
    Installs the Future Lab PX4 SITL + Gazebo Harmonic + ROS 2 Jazzy stack into an
    isolated WSL2 distro named "BumblebeeSim". Two modes:

      IMPORT (default when bumblebee-sim.tar sits next to this script; minutes):
        .\Install-BumblebeeSim.ps1 -Image .\bumblebee-sim.tar

      BUILD  (from source, 30-60 min, teacher / first machine):
        .\Install-BumblebeeSim.ps1 -Build

    Hardened vs. the original install.ps1 (each fixes a real failure observed on
    a clean Win 11 machine):
      * Targets Ubuntu-24.04 explicitly. ROS 2 Jazzy only exists on noble; a
        pre-existing Ubuntu-22.04 default distro made the original silently fail.
      * Creates the Linux user non-interactively with `!authenticate` + NOPASSWD.
        A plain sudo-group user with no TTY hangs `sudo -v` forever (the original
        also required a human to type a username/password and `exit`).
      * Installs pymavlink via pip -- there is no python3-pymavlink apt package on
        noble, which aborted the original apt install outright.
      * Stages inputs to an ASCII temp dir and strips CRLF, so a Cyrillic/space
        source path (e.g. OneDrive\Documents\win) can't break wslpath/arg passing.
      * Runs apt + needrestart fully non-interactively.
      * Judges success by inspecting artifacts (the process exit code is swallowed
        crossing the Windows->wsl boundary) and runs a live node/topic self-test.

.NOTES
    First-ever WSL enablement needs an elevated shell + one reboot. Everything
    after that runs without admin.
#>
[CmdletBinding()]
param(
    [string]$Image        = "",
    [string]$Seed         = "",
    [string]$DistroName   = "BumblebeeSim",
    [string]$InstallDir   = "$env:LOCALAPPDATA\BumblebeeSim",
    [string]$User         = "bumblebee",
    [string]$Password     = "bumblebee",
    [switch]$Build,
    [switch]$SkipSelfTest,
    [switch]$Force,
    [switch]$Yes
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

function Info($m) { Write-Host "[bumblebee] $m" -ForegroundColor Cyan }
function Good($m) { Write-Host "[bumblebee] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "[bumblebee] WARN: $m" -ForegroundColor Yellow }
function Fail($m) { Write-Host "[bumblebee] ERROR: $m" -ForegroundColor Red; exit 1 }
function Step($m) { Write-Host ""; Write-Host "==== $m ====" -ForegroundColor Magenta }

# Write text as a UTF-8 (no BOM), LF-only file -- safe to run as a bash script.
function Write-Lf($Path, $Text) {
    $lf = ($Text -replace "`r`n", "`n") -replace "`r", "`n"
    [System.IO.File]::WriteAllText($Path, $lf, (New-Object System.Text.UTF8Encoding($false)))
}
function Test-DistroExists($name) { & wsl.exe -d $name -e true *> $null; return ($LASTEXITCODE -eq 0) }
function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ---------------------------------------------------------------------------
Step "Preflight"
$osBuild = [System.Environment]::OSVersion.Version.Build   # NB: not $build — collides with [switch]$Build (case-insensitive)
Info "Windows build: $osBuild"
if ($osBuild -lt 19044) { Fail "Windows build $osBuild too old -- need Win 10 21H2 (19044)+ or Win 11 for WSLg." }
if ($osBuild -lt 22000) { Warn "Not Windows 11 -- should still work, but Win 11 is the tested target." }
if (-not (Get-CimInstance Win32_ComputerSystem).HypervisorPresent) {
    Warn "Hypervisor not detected yet. If WSL won't start, enable virtualization (Intel VT-x/AMD-V) in BIOS/UEFI."
}
$driveLetter = (Split-Path -Qualifier $InstallDir).TrimEnd(':')
$free = [math]::Round((Get-PSDrive $driveLetter).Free / 1GB, 1)
Info "Free space on ${driveLetter}: $free GB"
if ($free -lt 30) { Warn "Low disk space ($free GB). Recommend >= 30 GB (import) / 45 GB (build)." }

# ---------------------------------------------------------------------------
Step "Ensure WSL2 is present"
$wslReady = $false
if (Get-Command wsl.exe -ErrorAction SilentlyContinue) { & wsl.exe --status *> $null; $wslReady = ($LASTEXITCODE -eq 0) }
if (-not $wslReady) {
    if (-not (Test-Admin)) { Fail "WSL is not initialized. Re-run once from an ADMINISTRATOR PowerShell; it will enable WSL and ask for a reboot." }
    Info "Enabling the WSL platform (no distro yet)..."
    & wsl.exe --install --no-distribution
    if ($LASTEXITCODE -ne 0) { Fail "wsl --install failed. Enable virtualization in BIOS/UEFI and retry from an admin PowerShell." }
    Good "WSL enabled. REBOOT Windows now, then re-run this script (no admin needed after the reboot)."
    exit 0
}
& wsl.exe --set-default-version 2 *> $null
Good "WSL2 is ready."

# Pick mode: explicit -Image, else golden tar next to the script, else build.
if (-not $Image -and -not $Build) {
    $cand = Join-Path $ScriptDir "bumblebee-sim.tar"
    if (Test-Path -LiteralPath $cand) { $Image = $cand; Info "Found golden image: $cand" }
    else { $Build = $true; Info "No golden image next to the script -- using BUILD mode." }
}

# ---------------------------------------------------------------------------
Step "Check for an existing '$DistroName' distro"
if (Test-DistroExists $DistroName) {
    if ($Force) { Warn "Removing existing '$DistroName' (-Force)..."; & wsl.exe --unregister $DistroName; if ($LASTEXITCODE -ne 0) { Fail "Could not unregister '$DistroName'." } }
    else { Fail "A distro named '$DistroName' already exists. Remove it (wsl --unregister $DistroName) or pass -Force." }
}
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

# Stage files DIRECTLY into %TEMP% with a unique prefix -- do NOT create a new
# subdirectory. A freshly imported WSL distro sees new *files* in an existing dir
# via the 9P /mnt mount, but new *subdirectories* often stay invisible (even after
# --terminate), which broke staged scripts. %TEMP% is ASCII (Cyrillic/space-proof).
$StageDir   = $env:TEMP
$StagePfx   = "bbstage_" + [guid]::NewGuid().ToString("N").Substring(0,8) + "_"
$stageDrive = $StageDir.Substring(0,1).ToLower()
$stageRest  = $StageDir.Substring(2) -replace '\\','/'
function StageLocal($leaf) { Join-Path $StageDir "$StagePfx$leaf" }               # Windows path of a staged file
function StagedWsl($leaf)  { "/mnt/$stageDrive$stageRest/$StagePfx$leaf" }         # /mnt path of a staged file
function StageWsl($winPath) {                                                      # copy a Windows file in, return its /mnt path
    $leaf = Split-Path -Leaf $winPath
    Copy-Item -LiteralPath $winPath -Destination (StageLocal $leaf) -Force
    return (StagedWsl $leaf)
}

# A tiny CRLF-normalizer we can apply to any staged script before running it.
Write-Lf (StageLocal "normalize.sh") @'
#!/bin/bash
for f in "$@"; do [ -f "$f" ] && sed -i 's/\r$//' "$f"; done
echo NORM_OK
'@
$normWsl = StagedWsl "normalize.sh"

# A freshly imported/rebooted systemd distro races with the /mnt automount on
# first boot, so the very first command can run before /mnt/c is ready (staged
# scripts appear missing). Wait until C: is visible inside the distro. Called at
# the top of Normalize, which precedes every staged-script run (init-user,
# provision, verify, self-test) — so one guard covers them all.
function Wait-DistroMount {
    for ($i = 0; $i -lt 30; $i++) {
        & wsl.exe -d $DistroName -- test -e /mnt/c/Windows *> $null
        if ($LASTEXITCODE -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    Warn "/mnt/c not mounted in $DistroName after 30s -- staged scripts may fail."
}
function Normalize([string[]]$wslPaths) { Wait-DistroMount; & wsl.exe -d $DistroName -u root -- bash $normWsl @wslPaths *> $null }

try {
# ===========================================================================
if ($Image) {
    Step "IMPORT golden image -> $DistroName"
    if (-not (Test-Path -LiteralPath $Image)) { Fail "Image not found: $Image" }
    # wsl --import takes a Windows path (handled Unicode-aware on the Windows side),
    # so import the tar directly — no need to copy a 15+ GB file into staging.
    $imgFull = (Resolve-Path -LiteralPath $Image).Path
    Info "Importing (a few minutes; large tar)..."
    & wsl.exe --import $DistroName $InstallDir $imgFull --version 2
    if ($LASTEXITCODE -ne 0) { Fail "wsl --import failed." }
    & wsl.exe -d $DistroName -e id $User *> $null
    if ($LASTEXITCODE -eq 0) { & wsl.exe --manage $DistroName --set-default-user $User *> $null }
    Good "Image imported."
}
else {
    Step "BUILD from source -> $DistroName"

    # 1) Clone a pristine Ubuntu-24.04 rootfs into an isolated distro so we never
    #    disturb a user's own Ubuntu-24.04.
    $weInstalledBase = $false
    if (-not (Test-DistroExists "Ubuntu-24.04")) {
        Info "Fetching base Ubuntu-24.04 (download only, no launch)..."
        & wsl.exe --install -d Ubuntu-24.04 --no-launch
        if ($LASTEXITCODE -ne 0) { Fail "Failed to fetch Ubuntu-24.04." }
        $weInstalledBase = $true
    }
    $baseTar = StageLocal "ubuntu2404-base.tar"
    Info "Cloning base rootfs into '$DistroName'..."
    & wsl.exe --export "Ubuntu-24.04" $baseTar;                if ($LASTEXITCODE -ne 0) { Fail "Export of the Ubuntu-24.04 base failed." }
    & wsl.exe --import $DistroName $InstallDir $baseTar --version 2; if ($LASTEXITCODE -ne 0) { Fail "Import of '$DistroName' failed." }
    if ($weInstalledBase) { & wsl.exe --unregister "Ubuntu-24.04" *> $null }
    Remove-Item -LiteralPath $baseTar -Force -ErrorAction SilentlyContinue

    # 2) Non-interactive user init (root), then restart so wsl.conf takes effect.
    Write-Lf (StageLocal "init-user.sh") @"
#!/bin/bash
set -euo pipefail
U="$User"
if ! id "`$U" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "`$U"
    echo "`$U:$Password" | chpasswd
    usermod -aG sudo "`$U"
fi
printf 'Defaults:%s !authenticate\n%s ALL=(ALL) NOPASSWD:ALL\n' "`$U" "`$U" > /etc/sudoers.d/90-`$U
chmod 0440 /etc/sudoers.d/90-`$U
visudo -c >/dev/null
grep -q '^\[user\]' /etc/wsl.conf 2>/dev/null || printf '[user]\ndefault=%s\n' "`$U" >> /etc/wsl.conf
grep -q '^\[boot\]' /etc/wsl.conf 2>/dev/null || printf '[boot]\nsystemd=true\n' >> /etc/wsl.conf
echo INIT_OK
"@
    Normalize @((StagedWsl "init-user.sh"))
    Info "Configuring user '$User' (non-interactive)..."
    & wsl.exe -d $DistroName -u root -- bash (StagedWsl "init-user.sh")
    if ($LASTEXITCODE -ne 0) { Fail "User init failed." }
    & wsl.exe --terminate $DistroName *> $null

    # 3) Stage seed + provision.sh (ASCII, CRLF-stripped).
    if (-not $Seed) { $Seed = Join-Path $ScriptDir "bumblebee_src.tar.gz" }
    if (-not (Test-Path -LiteralPath $Seed)) { Fail "Seed archive not found: $Seed (produced by make_seed.sh)." }
    $provWin = Join-Path $ScriptDir "provision.sh"
    if (-not (Test-Path -LiteralPath $provWin)) { Fail "provision.sh not found next to the installer." }
    $seedWsl = StageWsl (Resolve-Path -LiteralPath $Seed).Path
    $provWsl = StageWsl (Resolve-Path -LiteralPath $provWin).Path
    Normalize @($provWsl)

    # 4) Provision (long). Exit code is unreliable here -- verified by artifacts next.
    Info "Provisioning ROS 2 + Gazebo + PX4 and building the workspace."
    Info "This is the long part (30-60 min). Progress streams below:"
    & wsl.exe -d $DistroName -- bash -lc "export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a NEEDRESTART_SUSPEND=1; bash '$provWsl' '$seedWsl' < /dev/null"
    Good "Provision step finished -- verifying."
}

# ===========================================================================
Step "Verify install (artifact check)"
Write-Lf (StageLocal "verify.sh") @'
#!/bin/bash
ok=1
have(){ if eval "$1" >/dev/null 2>&1; then echo "  [OK]   $2"; else echo "  [MISS] $2"; ok=0; fi; }
source /opt/ros/jazzy/setup.bash 2>/dev/null
have "command -v ros2"                            "ros2 CLI"
have "test -d /opt/ros/jazzy"                      "ROS 2 Jazzy"
have "command -v gz"                               "Gazebo (gz)"
have "test -f \$HOME/ros2_ws/install/setup.bash"   "workspace built"
have "test -e \$HOME/PX4-Autopilot/build"          "PX4 SITL built"
have "python3 -c 'import pymavlink'"               "pymavlink importable"
have "test -x /usr/local/bin/sim-run"              "sim-run command"
echo "VERIFY_RESULT=$ok"
'@
Normalize @((StagedWsl "verify.sh"))
$verOut = & wsl.exe -d $DistroName -- bash (StagedWsl "verify.sh")
$verOut | ForEach-Object { Write-Host "  $_" }
if (($verOut -join "`n") -notmatch "VERIFY_RESULT=1") { Fail "Verification failed -- stack incomplete (see [MISS] lines)." }
Good "All components present."

# ---------------------------------------------------------------------------
if (-not $SkipSelfTest) {
    Step "Self-test (headless launch + live node/topic checks, ~2 min)"
    $selfArg = ""
    $selfWin = Join-Path $ScriptDir "selftest.sh"
    if (Test-Path -LiteralPath $selfWin) { $selfArg = StageWsl (Resolve-Path -LiteralPath $selfWin).Path }
    Write-Lf (StageLocal "run-selftest.sh") @'
#!/bin/bash
# $1 = /mnt path to selftest.sh (optional). Boots the sim headless, then judges
# PASS on the essential LIVE signals (mavros node + camera frames + MAVROS state).
# selftest.sh detail is printed for info but does not gate the result -- its strict
# exit flags a cosmetic node-name mismatch (aruco_detect) even when all works.
# NB: no `set -u` -- sourcing ROS setup.bash references unbound vars and would exit.
set -o pipefail
SRC="${1:-}"
sudo mkdir -p /opt/bumblebee
if [ -n "$SRC" ] && [ -f "$SRC" ]; then
  sudo cp "$SRC" /opt/bumblebee/selftest.sh; sudo sed -i 's/\r$//' /opt/bumblebee/selftest.sh; sudo chmod +x /opt/bumblebee/selftest.sh
fi
source /opt/ros/jazzy/setup.bash 2>/dev/null
source "$HOME/ros2_ws/install/setup.bash" 2>/dev/null
export RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}"
RS="$HOME/ros2_ws/install/bumblebee_sim/share/bumblebee_sim/scripts/run_sim.sh"
[ -f "$RS" ] || { echo "  [FAIL] run_sim.sh missing at $RS"; echo "SELFTEST_RC=1"; exit 1; }
HEADLESS=1 bash "$RS" >/tmp/sim_boot.log 2>&1 || true
up=0
for i in $(seq 1 50); do
  if ros2 node list 2>/dev/null | grep -q mavros; then up=1; break; fi
  sleep 3
done
if [ "$up" != 1 ]; then
  echo "  [FAIL] stack did not come up within ~150s (see /tmp/sim_boot.log)"
  echo "SELFTEST_RC=1"; exit 1
fi
cam=0; for i in $(seq 1 20); do timeout 3 ros2 topic echo --once /main_camera/image_raw --field height >/dev/null 2>&1 && { cam=1; break; }; sleep 3; done
st=0; timeout 6 ros2 topic echo --once /mavros/state >/dev/null 2>&1 && st=1
echo "  [ OK ] mavros node up"
echo "  [$( [ "$cam" = 1 ] && echo ' OK ' || echo 'FAIL' )] camera frames (/main_camera/image_raw)"
echo "  [$( [ "$st" = 1 ] && echo ' OK ' || echo 'FAIL' )] MAVROS state (PX4 link)"
if [ -x /opt/bumblebee/selftest.sh ]; then echo "  --- selftest.sh detail ---"; bash /opt/bumblebee/selftest.sh 2>&1 | sed 's/^/    /' || true; fi
rc=1; [ "$up" = 1 ] && [ "$cam" = 1 ] && [ "$st" = 1 ] && rc=0
tmux kill-session -t bumblebee_sim 2>/dev/null || true
pkill -f px4 2>/dev/null || true
pkill -f 'gz sim' 2>/dev/null || true
echo "SELFTEST_RC=$rc"
exit $rc
'@
    Normalize @((StagedWsl "run-selftest.sh"))
    Info "Booting the sim headless and probing nodes/topics..."
    $stOut = & wsl.exe -d $DistroName -- bash (StagedWsl "run-selftest.sh") $selfArg
    $stOut | ForEach-Object { Write-Host "  $_" }
    if (($stOut -join "`n") -match "SELFTEST_RC=0") { Good "Self-test passed -- nodes and topics are live." }
    else { Warn "Self-test did not fully pass. Components are installed (verify OK); run run-sim.bat and check /tmp/sim_boot.log in WSL." }
}

Step "Done"
Good "Launch the simulator:  double-click run-sim.bat  (Gazebo opens via WSLg)"
Good "Dashboard:             http://localhost:8000/gcs.html"
Good "Roll out to a class:   export-golden.ps1  ->  students run this with -Image bumblebee-sim.tar"
}
finally {
    Get-ChildItem -LiteralPath $StageDir -Filter "$StagePfx*" -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
}
