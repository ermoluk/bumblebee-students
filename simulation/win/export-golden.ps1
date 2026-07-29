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

# export-golden.ps1 - export the provisioned WSL distro as a golden image
# for classroom rollout. Students then run: install.ps1 -Image bumblebee-sim.tar
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File export-golden.ps1 [-Out D:\bumblebee-sim.tar]

param(
    [string]$DistroName = "",
    [string]$Out = "$PSScriptRoot\bumblebee-sim.tar"
)

$ErrorActionPreference = "Stop"
function Fail($msg) { Write-Host "[export] ERROR: $msg" -ForegroundColor Red; exit 1 }
function Info($msg) { Write-Host "[export] $msg" -ForegroundColor Yellow }

if ($DistroName -eq "") {
    foreach ($d in @("BumblebeeSim", "Ubuntu-24.04")) {
        wsl.exe -d $d -e true *> $null
        if ($LASTEXITCODE -eq 0) { $DistroName = $d; break }
    }
    if ($DistroName -eq "") { Fail "No provisioned distro found (BumblebeeSim / Ubuntu-24.04)." }
}

Info "Exporting '$DistroName' -> $Out (expect 15-25 GB, use a big/external drive)..."
wsl.exe --terminate $DistroName *> $null
wsl.exe --export $DistroName $Out
if ($LASTEXITCODE -ne 0) { Fail "wsl --export failed." }

$sizeGB = [math]::Round((Get-Item $Out).Length / 1GB, 1)
Info "Done: $Out ($sizeGB GB)"
Info "Student machines: copy the tar + win\ folder, then run: install.ps1 -Image bumblebee-sim.tar"
