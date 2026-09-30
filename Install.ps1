#Requires -RunAsAdministrator
<#
.SYNOPSIS
    AMD Phoenix Driver Installer - Windows Server 2025
.DESCRIPTION
    Installs all AMD drivers (GPU, Audio, NPU, optional Pluton) on
    Windows Server 2025 with AMD Phoenix APU (Radeon 780M).

    What it does:
      1. Enables test signing + nointegritychecks (reboot required)
      2. Creates/reuses a self-signed code signing certificate
      3. Installs Windows SDK + WDK if needed (signtool, inf2cat, devcon)
      4. Patches the GPU INF for Server 2025 (see notes below)
      5. Rebuilds and signs all driver catalogs
      6. Installs all drivers (devcon force for the GPU if needed)

    GPU INF patching (the important part):
      - Removes duplicate INF sections (broken patcher output)
      - Fills the uncapped Server model sections
        [ATI.Mfg.NTamd64.10.0.3] and [ATI.Mfg.NTamd64]
        with the hardware ID list from the ..16299 sections.
      - Reason: Windows Server 2025 (build 26100) ignores the
        "NTamd64.10.0.3..16299" decorated sections, so the device
        finds "no compatible drivers" (0xe0000228) even though the
        exact HWID is listed there.
      - The test-signed driver also ranks below the inbox Basic
        Display Adapter, so a forced install via devcon is used
        as fallback.

.NOTES
    GPU:   AMD Radeon(TM) 780M - PCI\VEN_1002&DEV_15BF&SUBSYS_15BF1002&REV_D2
    Audio: AMD Audio CoProcessor - PCI\VEN_1022&DEV_15E2
    NPU:   AMD NPU Compute Accelerator - PCI\VEN_1022&DEV_1502
#>

param(
    [switch]$NoReboot,
    [switch]$PatchOnly   # Only patch the GPU INF, then exit (for testing)
)

$ErrorActionPreference = 'Stop'
# ============================================================
# GPU INF PATCH
#   1. Remove duplicate sections (broken upstream patcher)
#   2. Fill empty [ATI.Mfg.NTamd64.10.0.3] with the HWID list
#      from [ATI.Mfg.NTamd64.10.0.3..16299]
#   3. Add [ATI.Mfg.NTamd64] fallback section
#   4. Register plain NTamd64 in the Manufacturer line
#   Idempotent: skips if [ATI.Mfg.NTamd64] already exists.
# ============================================================
function Patch-GpuInf {
    param($infPath)

    if (-not (Test-Path $infPath)) { FAIL "INF not found: $infPath"; return $false }

    $lines = [System.Collections.Generic.List[string]]([System.IO.File]::ReadAllLines($infPath))

    # already patched?
    if (($lines | Where-Object { $_ -match '^\s*\[ATI\.Mfg\.NTamd64\]\s*$' }).Count -gt 0) {
        OK "GPU INF already patched - nothing to do"
        return $true
    }

    # --- 1) dedupe sections (keep first occurrence) ---
    $out = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    $skip = $false
    foreach ($l in $lines) {
        if ($l -match '^\s*\[([^\]]+)\]') {
            $n = $Matches[1].Trim()
            if ($seen.ContainsKey($n)) { $skip = $true; continue }
            $seen[$n] = $true; $skip = $false
            $out.Add($l); continue
        }
        if ($skip) { continue }
        $out.Add($l)
    }
    OK ("Dedupe: {0} -> {1} lines, {2} unique sections" -f $lines.Count, $out.Count, $seen.Count)

    # --- 2) extract HWID lines from the ..16299 Server section ---
    $secLines = New-Object System.Collections.Generic.List[string]
    $inSec = $false
    foreach ($l in $out) {
        if ($l -match '^\s*\[ATI\.Mfg\.NTamd64\.10\.0\.3\.\.16299\]') { $inSec = $true; continue }
        if ($inSec -and $l -match '^\s*\[') { break }
        if ($inSec) { $secLines.Add($l) }
    }
    if ($secLines.Count -eq 0) { FAIL "No ..16299 Server model section found - unexpected INF layout"; return $false }
    OK ("Extracted {0} HWID lines from ..16299 section" -f $secLines.Count)

    # --- 3) fill empty [ATI.Mfg.NTamd64.10.0.3] ---
    $idx303 = -1
    for ($i = 0; $i -lt $out.Count; $i++) { if ($out[$i] -match '^\s*\[ATI\.Mfg\.NTamd64\.10\.0\.3\]\s*$') { $idx303 = $i; break } }
    if ($idx303 -lt 0) { FAIL "[ATI.Mfg.NTamd64.10.0.3] section not found"; return $false }
    $out.InsertRange($idx303 + 1, [string[]]$secLines)
    OK "Filled [ATI.Mfg.NTamd64.10.0.3]"

    # --- 4) fallback section [ATI.Mfg.NTamd64] before [AMDOCLComponent] ---
    $idxOcl = -1
    for ($i = 0; $i -lt $out.Count; $i++) { if ($out[$i] -match '^\s*\[AMDOCLComponent\]') { $idxOcl = $i; break } }
    if ($idxOcl -lt 0) { $idxOcl = $out.Count }
    $fb = New-Object System.Collections.Generic.List[string]
    $fb.Add('')
    $fb.Add('; --- fallback: any NT x64 ---')
    $fb.Add('[ATI.Mfg.NTamd64]')
    $fb.AddRange([string[]]$secLines)
    $out.InsertRange($idxOcl, [string[]]$fb)
    OK "Added [ATI.Mfg.NTamd64] fallback section"

    # --- 5) Manufacturer line: register plain NTamd64 ---
    for ($i = 0; $i -lt $out.Count; $i++) {
        if ($out[$i] -match '^%ATI%\s*=\s*ATI\.Mfg\s*,\s*NTamd64\.') {
            if ($out[$i] -notmatch 'ATI\.Mfg\s*,\s*NTamd64,') {
                $out[$i] = $out[$i] -replace '(ATI\.Mfg\s*,)', '$1 NTamd64,'
            }
            break
        }
    }

    [System.IO.File]::WriteAllLines($infPath, $out)
    OK ("GPU INF patched: {0} lines written" -f $out.Count)
    return $true
}

# ============================================================
# PLUTON INF PATCH (same decoration trap as the GPU INF)
#   The HWID line only lives in [Standard.NTamd64.10.0...14393];
#   the ...22000 section is empty and build 26100 matches nothing.
#   Fill the ...22000 section + add uncapped [Standard.NTamd64].
#   Idempotent: skips if [Standard.NTamd64] already exists.
# ============================================================
function Patch-PlutonInf {
    param($infPath)

    if (-not (Test-Path $infPath)) { return $false }
    $lines = [System.Collections.Generic.List[string]]([System.IO.File]::ReadAllLines($infPath))

    if (($lines | Where-Object { $_ -match '^\s*\[Standard\.NTamd64\]\s*$' }).Count -gt 0) {
        OK "Pluton INF already patched"
        return $true
    }

    $hwid = '%Pluton.DeviceDesc%=Null_Pluton_Device, ACPI\MSFT0200'
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[Standard\.NTamd64\.10\.0\.\.\.22000\]') {
            $lines.Insert($i + 1, $hwid); $i++
            continue
        }
        if ($lines[$i] -match '^\s*\[Null_Pluton_Device\.NT\]') {
            $fb = @('', '; --- fallback: any NT x64 ---', '[Standard.NTamd64]', $hwid)
            $lines.InsertRange($i, [string[]]$fb); $i += 5
        }
    }
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^%STD%=Standard,' -and $lines[$i] -notmatch 'NTamd64,') {
            $lines[$i] = $lines[$i] -replace '(Standard,)', '$1 NTamd64,'
            break
        }
    }
    [System.IO.File]::WriteAllLines($infPath, $lines)
    OK "Pluton INF patched"
    return $true
}

$root = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- helpers ---
$script:step = 1
function Step { param($m) Write-Host "`n=== [$($script:step)] $m ===" -ForegroundColor Cyan; $script:step++ }
function OK   { param($m) Write-Host "  [OK] $m" -ForegroundColor Green }
function WARN { param($m) Write-Host "  [!]  $m" -ForegroundColor Yellow }
function FAIL { param($m) Write-Host "  [X]  $m" -ForegroundColor Red }

Write-Host ""
Write-Host " ========================================================" -ForegroundColor White
Write-Host "   AMD Phoenix Driver Installer - Windows Server 2025"    -ForegroundColor Cyan
Write-Host "   GPU: AMD Radeon(TM) 780M  |  Audio  |  NPU"            -ForegroundColor Cyan
Write-Host " ========================================================" -ForegroundColor White

# --- paths ---
$gpuInf    = "$root\Drivers\GPU\u0410304.inf"
$audioDir  = "$root\Drivers\Audio"
$npuDir    = "$root\Drivers\NPU"
$plutonInf = "$root\Drivers\Pluton\plutonnull.inf"

# ============================================================
# 1) FILE CHECK (incl. binaries - incomplete extractions are
#    the most common failure: release zips must be extracted
#    into the Drivers folders, not just INF/CAT)
# ============================================================
Step "Checking files"
$required = @(
    $gpuInf,
    "$audioDir\amdacpbus.inf", "$audioDir\amdacpbus.sys",
    "$audioDir\amdacpafd.inf", "$audioDir\amdacpafd.sys",
    "$audioDir\acpcfg0001.dat",
    "$npuDir\kipudrv.inf", "$npuDir\ipustack.sys"
)
$missing = $required | Where-Object { -not (Test-Path $_) }
if ($missing) {
    FAIL "Missing files (incomplete extraction?):"
    $missing | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
    Write-Host "  Extract ALL release zips into the Drivers\ folders first." -ForegroundColor Yellow
    Read-Host "`nPress Enter to exit"
    exit 1
}
OK "All driver files present"

if ($PatchOnly) {
    Patch-GpuInf $gpuInf
    return
}

# ============================================================
# 2) TEST SIGNING
# ============================================================
Step "Checking test signing"

$ts = bcdedit /enum | Select-String "testsigning\s+Yes" -Quiet
$ni = bcdedit /enum | Select-String "nointegritychecks\s+Yes" -Quiet
$rebootNeeded = $false

if (-not $ts) { bcdedit /set testsigning on | Out-Null; OK "testsigning ON"; $rebootNeeded = $true }
else { OK "testsigning already active" }

if (-not $ni) { bcdedit /set nointegritychecks on | Out-Null; OK "nointegritychecks ON"; $rebootNeeded = $true }
else { OK "nointegritychecks already active" }

if ($rebootNeeded) {
    WARN "REBOOT REQUIRED - settings only take effect after reboot"
    if (-not $NoReboot) {
        $a = Read-Host "  Reboot now? (Y/N)"
        if ($a -match '^[jJyY]') {
            shutdown /r /t 5 /c "AMD Driver Installer - Reboot"
            exit 0
        }
    }
    WARN "Cannot continue without reboot."
    Read-Host "Press Enter to exit"
    exit 2
}

# ============================================================
# 3) CERTIFICATE
# ============================================================
Step "Code signing certificate"

$certName = "AMD Driver Test"
$cert = Get-ChildItem Cert:\LocalMachine\My -CodeSigningCert -ErrorAction SilentlyContinue |
        Where-Object { $_.Subject -eq "CN=$certName" -and $_.NotAfter -gt (Get-Date) } |
        Select-Object -First 1

if (-not $cert) {
    $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject "CN=$certName" `
            -CertStoreLocation Cert:\LocalMachine\My -NotAfter (Get-Date).AddYears(5)
    $tmp = "$env:TEMP\amd_cert.cer"
    Export-Certificate -Cert $cert -FilePath $tmp -Force | Out-Null
    Import-Certificate -FilePath $tmp -CertStoreLocation Cert:\LocalMachine\Root -Confirm:$false | Out-Null
    Import-Certificate -FilePath $tmp -CertStoreLocation Cert:\LocalMachine\TrustedPublisher -Confirm:$false | Out-Null
    Remove-Item $tmp -ErrorAction SilentlyContinue
    OK "New certificate: $($cert.Thumbprint)"
} else {
    OK "Existing certificate: $($cert.Thumbprint)"
}

# ============================================================
# 4) SDK + WDK (signtool, inf2cat, devcon)
# ============================================================
Step "Signing tools (SDK + WDK)"

$kitsBase = "C:\Program Files (x86)\Windows Kits\10"

function Find-Tool {
    param($filter, $pattern = "x64")
    Get-ChildItem "$kitsBase\bin" -Recurse -Filter $filter -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match $pattern -and $_.FullName -notmatch "arm64" } |
        Select-Object -First 1 -ExpandProperty FullName
}

$signtool = Find-Tool "signtool.exe"
$inf2cat  = Find-Tool "Inf2Cat.exe" ""   # any arch

if (-not $signtool) {
    Write-Host "  Installing Windows SDK..." -ForegroundColor Gray
    winget install Microsoft.WindowsSDK.10.0.26100 --accept-package-agreements --accept-source-agreements --silent 2>&1 | Out-Null
    $signtool = Find-Tool "signtool.exe"
    if ($signtool) { OK "SDK installed" } else { FAIL "SDK installation failed!"; exit 1 }
} else { OK "signtool present" }

if (-not $inf2cat) {
    Write-Host "  Installing Windows WDK..." -ForegroundColor Gray
    winget install Microsoft.WindowsWDK.10.0.26100 --accept-package-agreements --accept-source-agreements --silent 2>&1 | Out-Null
    $inf2cat = Find-Tool "Inf2Cat.exe" ""
    if ($inf2cat) { OK "WDK installed" } else { FAIL "WDK installation failed!"; exit 1 }
} else { OK "inf2cat present" }

$devcon = Get-ChildItem "$kitsBase\Tools" -Recurse -Filter "devcon.exe" -ErrorAction SilentlyContinue |
          Where-Object { $_.FullName -match "x64" -and $_.FullName -notmatch "arm64" } |
          Select-Object -First 1 -ExpandProperty FullName
if ($devcon) { OK "devcon present: $devcon" } else { WARN "devcon not found (WDK Tools) - force-install fallback unavailable" }

# ============================================================
# 5) PATCH GPU INF (dedupe + Server model sections)
# ============================================================
Step "Patching GPU INF for Server 2025"
Patch-GpuInf $gpuInf

# ============================================================
# 6) REBUILD + SIGN CATALOGS (GPU, Audio, NPU)
# ============================================================
Step "Rebuilding driver catalogs"

foreach ($dir in @("$root\Drivers\GPU", $audioDir, $npuDir)) {
    if (-not (Test-Path $dir)) { continue }
    Get-ChildItem $dir -Filter "*.cat" -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    & $inf2cat /driver:"$dir" /os:10_X64,ServerRS5_X64,Server10_X64 2>&1 | Out-Null
}

Step "Signing catalog files"

$signed = 0; $failed = 0
Get-ChildItem "$root\Drivers" -Filter "*.cat" -Recurse | ForEach-Object {
    & $signtool sign /sm /sha1 $cert.Thumbprint /fd SHA256 $_.FullName 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { $signed++; OK $_.Name } else { $failed++; WARN "Could not sign: $($_.Name)" }
}
if ($failed -gt 0) { WARN "$failed catalog(s) failed to sign" }

# ============================================================
# 7) GPU DRIVER INSTALL
# ============================================================
Step "Installing GPU driver (AMD Radeon 780M)"

$r = pnputil /add-driver $gpuInf /install 2>&1
$ro = $r -join "`n"
$gpuBound = $false
if ($ro -match "installed on device") {
    OK "GPU driver installed and assigned to device"
    $gpuBound = $true
} elseif ($ro -match "Added driver packages:\s+1") {
    OK "GPU driver added to Driver Store"
} else {
    WARN "GPU result: $ro"
}

if (-not $gpuBound -and $devcon) {
    # Forced install: the test-signed driver ranks below the inbox
    # Basic Display Adapter, so normal selection will never pick it.
    WARN "Device not bound yet - forcing via devcon"
    & $devcon update $gpuInf "PCI\VEN_1002&DEV_15BF&SUBSYS_15BF1002&REV_D2" 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { OK "devcon: drivers installed successfully" }
    else { WARN "devcon update failed (exit $LASTEXITCODE)" }
}

# ============================================================
# 8) AUDIO + NPU DRIVERS
# ============================================================
Step "Installing AMD Audio + NPU drivers"

pnputil /add-driver "$audioDir\*.inf" /install /subdirs 2>&1 | Out-Null
OK "Audio drivers added"

pnputil /add-driver "$npuDir\*.inf" /install /subdirs 2>&1 | Out-Null
OK "NPU driver added"

# ============================================================
# 9) PLUTON (optional)
# ============================================================
if (Test-Path $plutonInf) {
    Step "Pluton null driver (optional)"
    Patch-PlutonInf $plutonInf
    if (Test-Path "$root\Drivers\Pluton\plutonnull.cat") {
        Remove-Item "$root\Drivers\Pluton\plutonnull.cat" -Force -ErrorAction SilentlyContinue
        & $inf2cat /driver:"$root\Drivers\Pluton" /os:10_X64,ServerRS5_X64,Server10_X64 2>&1 | Out-Null
        & $signtool sign /sm /sha1 $cert.Thumbprint /fd SHA256 "$root\Drivers\Pluton\plutonnull.cat" 2>&1 | Out-Null
    }
    pnputil /add-driver $plutonInf /install 2>&1 | Out-Null
    OK "Pluton added (patched for Server)"
}

# ============================================================
# RESULT
# ============================================================
Write-Host ""
Write-Host " ========================================================" -ForegroundColor Green
Write-Host "   INSTALLATION COMPLETE!" -ForegroundColor Green
Write-Host " ========================================================" -ForegroundColor Green
Write-Host ""

Write-Host "  Device status (Display / Audio / NPU):" -ForegroundColor Cyan
Get-PnpDevice | Where-Object { $_.InstanceId -match 'DEV_15BF|DEV_15E2|DEV_1502' } |
    ForEach-Object { Write-Host ("    {0,-40} {1,-8} {2}" -f $_.FriendlyName, $_.Status, $_.Problem) }

$prob = Get-PnpDevice | Where-Object { $_.Status -eq 'Error' }
Write-Host ""
if (-not $prob) {
    Write-Host "  No problem devices - everything works!" -ForegroundColor Green
} else {
    WARN "$($prob.Count) problem device(s) remaining:"
    $prob | ForEach-Object { Write-Host ("    {0}  ({1}, {2})" -f $_.FriendlyName, $_.Class, $_.Problem) -ForegroundColor Yellow }
}

Write-Host ""
Write-Host "  Note: Test signing is active - a desktop watermark may appear." -ForegroundColor Gray
Write-Host ""
Read-Host "Press Enter to exit"
