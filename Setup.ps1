#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Driver package setup for AMD Phoenix Driver Pack - Windows Server 2025
.DESCRIPTION
    Downloads (optional) and extracts the driver release zips into the
    correct Drivers\ subfolders. Run this BEFORE Install.ps1.

    Why this script exists: the release zip "Drivers-Audio-NPU.zip"
    contains Audio AND NPU files MIXED at the archive root. Extracting
    it naively leaves Drivers\Audio and Drivers\NPU without their
    binaries (.sys, .dat, .xclbin) and the driver import fails with
    "file not found". This script splits the archive correctly.

    File classification (proven on a live Server 2025 install):
      Audio:  amdacpbus.*, amdacpafd.*, acpcfg*.dat, acpimg*.dat,
              amdmvaoem.dll, amdacpbusext\ (whole subfolder)
      NPU:    everything else (kipudrv.*, ipustack.sys, *.xclbin,
              RadeonML*.dll, xrt*.dll, rml\, DPU_Sequence\, ...)
      Skip:   plutonnull.* (ships in the repo), Readme.txt, ReleaseNotes.txt

.PARAMETER ZipPath
    Folder that contains the release zips. Default: script directory.

.PARAMETER Download
    Download missing zips from the GitHub release first.

.PARAMETER RepoSlug
    GitHub repo slug used for -Download.
#>

param(
    [string]$ZipPath = $PSScriptRoot,
    [switch]$Download,
    [string]$RepoSlug = 'IT-Kuny/AMD-Phoenix-Driver-WinServer2025'
)

$ErrorActionPreference = 'Stop'

function OK   { param($m) Write-Host "  [OK] $m" -ForegroundColor Green }
function FAIL { param($m) Write-Host "  [X]  $m" -ForegroundColor Red }

Write-Host ""
Write-Host " === Driver Package Setup - AMD Phoenix (Server 2025) ===" -ForegroundColor Cyan
Write-Host ""

$gpuZip = Join-Path $ZipPath 'Drivers-GPU.zip'
$anZip  = Join-Path $ZipPath 'Drivers-Audio-NPU.zip'

# --- optional download ---
if ($Download) {
    foreach ($z in @($gpuZip, $anZip)) {
        if (Test-Path $z) { OK "$(Split-Path $z -Leaf) already present"; continue }
        $name = Split-Path $z -Leaf
        $url  = "https://github.com/$RepoSlug/releases/latest/download/$name"
        Write-Host "  downloading $name ..." -ForegroundColor Gray
        Invoke-WebRequest -Uri $url -OutFile $z
        OK "downloaded $name"
    }
}

# --- check zips ---
$missing = @($gpuZip, $anZip) | Where-Object { -not (Test-Path $_) }
if ($missing) {
    FAIL "Missing zips:"
    $missing | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
    Write-Host "  Download them from https://github.com/$RepoSlug/releases" -ForegroundColor Yellow
    Write-Host "  or re-run with -Download" -ForegroundColor Yellow
    exit 1
}

Add-Type -AssemblyName System.IO.Compression.FileSystem

# --- GPU ---
Write-Host "`n [1/3] Extracting GPU driver..." -ForegroundColor Cyan
$gpuDir = Join-Path $PSScriptRoot 'Drivers\GPU'
if (Test-Path $gpuDir) { Remove-Item $gpuDir -Recurse -Force }
New-Item -ItemType Directory $gpuDir -Force | Out-Null
[System.IO.Compression.ZipFile]::ExtractToDirectory($gpuZip, $gpuDir)
# flatten if the zip has a single wrapping folder
if (-not (Test-Path (Join-Path $gpuDir 'u0410304.inf'))) {
    $inner = Get-ChildItem $gpuDir -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'u0410304.inf') } | Select-Object -First 1
    if ($inner) { Get-ChildItem $inner.FullName | Move-Item -Destination $gpuDir; Remove-Item $inner.FullName -Force }
}
OK "GPU: $((Get-ChildItem $gpuDir -Recurse -File).Count) files"

# --- Audio + NPU (mixed archive, split it) ---
Write-Host "`n [2/3] Extracting + splitting Audio/NPU driver..." -ForegroundColor Cyan
$stage = Join-Path $env:TEMP ('amd-an-' + [guid]::NewGuid().ToString('N'))
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
[System.IO.Compression.ZipFile]::ExtractToDirectory($anZip, $stage)

$audioDir = Join-Path $PSScriptRoot 'Drivers\Audio'
$npuDir   = Join-Path $PSScriptRoot 'Drivers\NPU'
foreach ($d in @($audioDir, $npuDir)) { if (Test-Path $d) { Remove-Item $d -Recurse -Force }; New-Item -ItemType Directory $d -Force | Out-Null }

$audioRoot = @('amdacpbus.inf','amdacpbus.cat','amdacpbus.sys','amdacpafd.inf','amdacpafd.cat','amdacpafd.sys','amdmvaoem.dll')
$skipFiles = @('plutonnull.inf','plutonnull.cat','Readme.txt','ReleaseNotes.txt')

$zip = [System.IO.Compression.ZipFile]::OpenRead($anZip)
foreach ($e in $zip.Entries) {
    $name = Split-Path $e.FullName -Leaf
    $dir  = [System.IO.Path]::GetDirectoryName($e.FullName) -replace '/','\'
    if (-not $name) { continue }
    if ($skipFiles -contains $name) { continue }
    if ($dir -and $dir -like 'amdacpbusext*') { $target = "$audioDir\$dir" }
    elseif (-not $dir -and ($audioRoot -contains $name -or $name -like 'acpcfg*.dat' -or $name -like 'acpimg*.dat')) { $target = $audioDir }
    else { $target = "$npuDir\$(if ($dir) { $dir } else { '' })" }
    New-Item -ItemType Directory $target -Force | Out-Null
    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, (Join-Path $target $name), $true)
}
$zip.Dispose()
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
OK "Audio: $((Get-ChildItem $audioDir -Recurse -File).Count) files"
OK "NPU:   $((Get-ChildItem $npuDir -Recurse -File).Count) files"

# --- verify ---
Write-Host "`n [3/3] Verifying..." -ForegroundColor Cyan
$required = @(
    'Drivers\GPU\u0410304.inf',
    'Drivers\Audio\amdacpbus.inf', 'Drivers\Audio\amdacpbus.sys', 'Drivers\Audio\acpcfg0001.dat',
    'Drivers\NPU\kipudrv.inf', 'Drivers\NPU\ipustack.sys'
)
$bad = $required | Where-Object { -not (Test-Path (Join-Path $PSScriptRoot $_)) }
if ($bad) {
    FAIL "Verification failed:"
    $bad | ForEach-Object { Write-Host "    missing: $_" -ForegroundColor Red }
    exit 1
}
OK "All required files in place"

Write-Host "`n Setup complete. Now run Install.bat (or Install.ps1)." -ForegroundColor Green
Write-Host ""
