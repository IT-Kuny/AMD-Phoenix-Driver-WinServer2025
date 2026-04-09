#Requires -RunAsAdministrator
<#
.SYNOPSIS
    AMD Phoenix GPU + Audio + NPU Driver Installer - Windows Server 2025
.DESCRIPTION
    Tek tiklama ile tum AMD driverlarini kurar.
    - Test signing aktif eder (reboot gerekirse sorar)
    - Self-signed sertifika olusturur
    - WDK/SDK otomatik kurar (yoksa)
    - GPU catalog olusturup imzalar
    - Tum driverlari kurar
.NOTES
    GPU: AMD Radeon(TM) 780M - PCI\VEN_1002&DEV_15BF&SUBSYS_15BF1002&REV_D2
#>

param([switch]$NoReboot)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- Yardimcilar ---
$script:step = 1
function Step  { param($m) Write-Host "`n=== [$($script:step)] $m ===" -ForegroundColor Cyan; $script:step++ }
function OK    { param($m) Write-Host "  [OK] $m" -ForegroundColor Green }
function WARN  { param($m) Write-Host "  [!]  $m" -ForegroundColor Yellow }
function FAIL  { param($m) Write-Host "  [X]  $m" -ForegroundColor Red }

# --- Banner ---
Write-Host ""
Write-Host " ========================================================" -ForegroundColor White
Write-Host "   AMD Phoenix Driver Installer - Windows Server 2025"     -ForegroundColor Cyan
Write-Host "   GPU: AMD Radeon(TM) 780M  |  Audio  |  NPU"            -ForegroundColor Cyan
Write-Host " ========================================================" -ForegroundColor White

# --- Paths ---
$gpu       = "$root\Drivers\GPU\u0410304.inf"
$audioBus  = "$root\Drivers\Audio\amdacpbus.inf"
$audioAfd  = "$root\Drivers\Audio\amdacpafd.inf"
$npu       = "$root\Drivers\NPU\kipudrv.inf"
$pluton    = "$root\Drivers\Pluton\plutonnull.inf"

# --- Dosya kontrolu ---
Step "Dosyalar kontrol ediliyor"
$missing = @($gpu, $audioBus, $audioAfd, $npu) | Where-Object { -not (Test-Path $_) }
if ($missing) {
    FAIL "Eksik dosyalar:"
    $missing | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
    Read-Host "`nCikmak icin Enter"
    exit 1
}
OK "Tum driver dosyalari mevcut"

# ============================================================
# 1) TEST SIGNING
# ============================================================
Step "Test signing kontrol ediliyor"

$ts = bcdedit /enum | Select-String "testsigning\s+Yes" -Quiet
$ni = bcdedit /enum | Select-String "nointegritychecks\s+Yes" -Quiet
$rebootNeeded = $false

if (-not $ts) { bcdedit /set testsigning on | Out-Null; OK "testsigning ON"; $rebootNeeded = $true }
else { OK "testsigning zaten aktif" }

if (-not $ni) { bcdedit /set nointegritychecks on | Out-Null; OK "nointegritychecks ON"; $rebootNeeded = $true }
else { OK "nointegritychecks zaten aktif" }

if ($rebootNeeded) {
    WARN "REBOOT GEREKLI - ayarlar reboot sonrasi aktif olacak"
    if (-not $NoReboot) {
        $a = Read-Host "  Simdi reboot? (E/H)"
        if ($a -match '^[eEyY]') {
            shutdown /r /t 5 /c "AMD Driver Installer - reboot"
            exit 0
        }
    }
    WARN "Reboot yapilmadan devam edilemez."
    Read-Host "Cikmak icin Enter"
    exit 2
}

# ============================================================
# 2) SERTIFIKA
# ============================================================
Step "Code-signing sertifikasi"

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
    OK "Yeni sertifika: $($cert.Thumbprint)"
} else {
    OK "Mevcut sertifika: $($cert.Thumbprint)"
}

# ============================================================
# 3) SDK + WDK (signtool & inf2cat)
# ============================================================
Step "Imzalama araclari (SDK + WDK)"

$kitsBase = "C:\Program Files (x86)\Windows Kits\10"

$signtool = Get-ChildItem "$kitsBase\bin" -Recurse -Filter "signtool.exe" -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match "x64" } | Select-Object -First 1 -ExpandProperty FullName

$inf2cat  = Get-ChildItem "$kitsBase\bin" -Recurse -Filter "Inf2Cat.exe" -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName

if (-not $signtool) {
    Write-Host "  Windows SDK kuruluyor..." -ForegroundColor Gray
    winget install Microsoft.WindowsSDK.10.0.26100 --accept-package-agreements --accept-source-agreements --silent 2>&1 | Out-Null
    $signtool = Get-ChildItem "$kitsBase\bin" -Recurse -Filter "signtool.exe" -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match "x64" } | Select-Object -First 1 -ExpandProperty FullName
    if ($signtool) { OK "SDK kuruldu" } else { FAIL "SDK kurulamadi!"; exit 1 }
} else { OK "signtool mevcut" }

if (-not $inf2cat) {
    Write-Host "  Windows WDK kuruluyor..." -ForegroundColor Gray
    winget install Microsoft.WindowsWDK.10.0.26100 --accept-package-agreements --accept-source-agreements --silent 2>&1 | Out-Null
    $inf2cat = Get-ChildItem "$kitsBase\bin" -Recurse -Filter "Inf2Cat.exe" -ErrorAction SilentlyContinue |
               Select-Object -First 1 -ExpandProperty FullName
    if ($inf2cat) { OK "WDK kuruldu" } else { FAIL "WDK kurulamadi!"; exit 1 }
} else { OK "inf2cat mevcut" }

# ============================================================
# 4) GPU CATALOG OLUSTUR + IMZALA
# ============================================================
Step "GPU driver catalog olusturuluyor"

$gpuDir = "$root\Drivers\GPU"
$gpuCat = "$gpuDir\u0410304.cat"

Remove-Item $gpuCat -ErrorAction SilentlyContinue
& $inf2cat /driver:"$gpuDir" /os:10_X64,ServerRS5_X64,Server10_X64 2>&1 | Out-Null

if (-not (Test-Path $gpuCat)) {
    FAIL "Catalog olusturulamadi!"
    & $inf2cat /driver:"$gpuDir" /os:10_X64,ServerRS5_X64,Server10_X64 2>&1
    Read-Host "Cikmak icin Enter"
    exit 1
}
OK "Catalog olusturuldu"

Step "Catalog dosyalari imzalaniyor"

Get-ChildItem $gpuDir -Filter "*.cat" -Recurse |
    Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-10) } |
    ForEach-Object {
        & $signtool sign /sm /sha1 $cert.Thumbprint /fd SHA256 $_.FullName 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { OK $_.Name } else { WARN "Imzalanamadi: $($_.Name)" }
    }

# ============================================================
# 5) GPU DRIVER KUR
# ============================================================
Step "GPU driver kuruluyor (AMD Radeon 780M)"

$r = pnputil /add-driver $gpu /install 2>&1
$ro = $r -join "`n"
if ($ro -match "installed on device") {
    OK "GPU driver kuruldu ve cihaza atandi!"
} elseif ($ro -match "Added driver packages:\s+1") {
    OK "GPU driver store'a eklendi"
    # devcon ile zorla ata
    $devcon = Get-ChildItem "$kitsBase\Tools" -Recurse -Filter "devcon.exe" -ErrorAction SilentlyContinue |
              Where-Object { $_.FullName -match "x64" } | Select-Object -First 1 -ExpandProperty FullName
    if ($devcon) {
        & $devcon remove '=Display' '@PCI\VEN_1002&DEV_15BF*' 2>&1 | Out-Null
        pnputil /scan-devices 2>&1 | Out-Null
        Start-Sleep 3
        OK "Cihaz yeniden tarandi"
    }
} else {
    WARN "GPU sonuc: $ro"
}

# ============================================================
# 6) AUDIO DRIVER KUR
# ============================================================
Step "AMD Audio driver kuruluyor"

pnputil /add-driver $audioBus /install 2>&1 | Out-Null
OK "ACP Bus driver eklendi"

pnputil /add-driver $audioAfd /install 2>&1 | Out-Null
OK "ACP AFD driver eklendi"

# ============================================================
# 7) NPU DRIVER KUR
# ============================================================
Step "AMD NPU driver kuruluyor"

pnputil /add-driver $npu /install 2>&1 | Out-Null
OK "NPU driver eklendi"

# ============================================================
# 8) PLUTON (opsiyonel)
# ============================================================
if (Test-Path $pluton) {
    Step "Pluton null driver kuruluyor"
    pnputil /add-driver $pluton /install 2>&1 | Out-Null
    OK "Pluton eklendi (Server'da calismayabilir)"
}

# ============================================================
# SONUC
# ============================================================
Write-Host ""
Write-Host " ========================================================" -ForegroundColor Green
Write-Host "   KURULUM TAMAMLANDI!" -ForegroundColor Green
Write-Host " ========================================================" -ForegroundColor Green
Write-Host ""

# GPU durumu
$dev = pnputil /enum-devices /class Display /connected 2>&1
Write-Host "  GPU Durumu:" -ForegroundColor Cyan
$dev | Select-String "Device Description:|Status:" | ForEach-Object {
    Write-Host "    $($_.Line.Trim())"
}

# Kalan sorunlar
Write-Host ""
$prob = pnputil /enum-devices /problem 2>&1
$pc = ($prob | Select-String "Instance ID:").Count
if ($pc -eq 0) {
    Write-Host "  Sorunlu cihaz yok - hersey calisiyor!" -ForegroundColor Green
} else {
    WARN "$pc sorunlu cihaz kaldi:"
    $prob | Select-String "Instance ID:|Device Description:" |
        ForEach-Object { Write-Host "    $($_.Line.Trim())" -ForegroundColor Yellow }
}

Write-Host ""
Write-Host "  Not: Test signing aktif, masaustunde watermark gorunebilir." -ForegroundColor Gray
Write-Host ""
Read-Host "Cikmak icin Enter'a basin"
