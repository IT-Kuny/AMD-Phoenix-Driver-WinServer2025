# AMD Phoenix Driver Pack - Windows Server 2025

Continuation of [fintechcoding/AMD-Phoenix-Driver-WinServer2025](https://github.com/fintechcoding/AMD-Phoenix-Driver-WinServer2025) with fixed installer (original history preserved below).

Complete AMD driver package (GPU + Audio + NPU) for **Windows Server 2025** with AMD Phoenix APUs (Ryzen 7000/8000 series with Radeon 780M / 760M iGPU).

**README languages:** [English (default)](README.md) | [Deutsch](README.de.md) | [Turkce](README.tr.md)

## The Problem

AMD does not officially support Windows Server 2025 for the Phoenix (Radeon 780M) integrated GPU. The official driver INF only targets `ProductType=1` (Workstation), causing Windows Server (`ProductType=3`) to fall back to the generic "Microsoft Basic Display Adapter". Audio (ACP) and NPU devices also remain without drivers.

On top of that, the INF decoration `NTamd64.10.0.3..16299` used by the Server patch is **ignored by Server 2025 (build 26100)** - the device finds "no compatible drivers" (`0xe0000228`) even though the exact hardware ID is listed. And since the driver is test-signed, it always **ranks below the inbox Basic Display Adapter**, so normal driver selection never picks it.

## What This Does

The installer automatically:

1. Enables `bcdedit /set testsigning on` and `nointegritychecks on` (reboot required)
2. Creates a self-signed code signing certificate ("AMD Driver Test") and adds it to Root + TrustedPublisher
3. Installs Windows SDK + WDK if needed (for `signtool`, `inf2cat` and `devcon`)
4. **Patches the GPU INF properly:**
   - Removes duplicate INF sections (broken patcher output shipped in earlier releases)
   - Fills the uncapped Server model sections `[ATI.Mfg.NTamd64.10.0.3]` and `[ATI.Mfg.NTamd64]` with the hardware ID list - these are the decorations that build 26100 actually honors
5. Rebuilds **all** catalogs (GPU, Audio, NPU) with `inf2cat` and signs them
6. Installs all drivers; uses a **forced install via `devcon update`** for the GPU if normal selection refuses (test-signed driver rank issue)

## Included Drivers

| Device | Hardware ID | Component | Version |
|---|---|---|---|
| AMD Radeon(TM) 780M | `PCI\VEN_1002&DEV_15BF&SUBSYS_15BF1002&REV_D2` | GPU Display | 32.0.12030.9 |
| AMD Audio CoProcessor | `PCI\VEN_1022&DEV_15E2` | ACP Bus + AFD Audio | 6.0.0.100 |
| NPU Compute Accelerator | `PCI\VEN_1022&DEV_1502` | AMD NPU MCDM | 32.0.203.231 |
| Microsoft Pluton | `ACPI\MSFT0200` | Pluton Null Driver (optional) | 1.0.0.2 |

## Installation

### Quick Install

1. Download the repo zip and extract it (or `git clone`)
2. **Run `Setup.ps1 -Download`** - downloads the release zips and extracts them into the correct `Drivers\` folders (the Audio/NPU archive contains mixed files and MUST be split - the script does this for you):
   ```powershell
   powershell -ExecutionPolicy Bypass -File Setup.ps1 -Download
   ```
   If you already downloaded `Drivers-GPU.zip` and `Drivers-Audio-NPU.zip` manually, drop them next to the scripts and run `Setup.ps1` without `-Download`.
3. **Double-click `Install.bat`** (auto-elevates to admin)
4. First run: enables test signing and asks for a **reboot**
5. After reboot: run `Install.bat` again - all drivers install automatically

### Manual Install

```powershell
# Run as Administrator
powershell -ExecutionPolicy Bypass -File Install.ps1
```

Test the INF patch only (no installation):

```powershell
powershell -ExecutionPolicy Bypass -File Install.ps1 -PatchOnly
```

## Expected Folder Structure

```
AMD-Phoenix-Driver-WinServer2025/
|- Setup.ps1                # Downloads + extracts driver zips (-Download)
|- Install.bat               # Double-click to install (auto-elevates)
|- Install.ps1               # Main installer script
|- README.md                 # This file (EN)
|- README.de.md              # German version
|- README.tr.md              # Turkish version
|- Drivers/
|  |- GPU/                   # AMD Radeon 780M display driver (~1.9 GB)
|  |  |- u0410304.inf        # AMD GPU INF (patched at install time)
|  |  |- B409433/            # GPU driver binaries (DLLs, firmware)
|  |  |- amdocl/             # OpenCL components
|  |  |- amdfendr/           # AMD FidelityFX
|  |  |- amdfdans/           # AMD noise suppression
|  |  |- amdpcibridge/       # PCI bridge extension
|  |  |- amdwin/             # AMD Windows components
|  |- Audio/                 # AMD ACP Audio drivers (~31 MB)
|  |  |- amdacpbus.inf/.sys  # ACP Bus driver
|  |  |- amdacpafd.inf/.sys  # ACP AFD audio driver
|  |  |- acpcfg*.dat, acpimg*.dat
|  |  |- amdacpbusext/       # ACP bus extension (CopyINF subpackage)
|  |- NPU/                   # AMD NPU driver (~228 MB)
|  |  |- kipudrv.inf         # NPU compute accelerator
|  |  |- ipustack.sys        # NPU kernel driver
|  |  |- *.xclbin, RadeonML*.dll, xrt*.dll, ...
|  |  |  |- Pluton/                # Microsoft Pluton null driver (~17 KB, IN REPO, pre-patched)
|     |- plutonnull.inf
```

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `0xe0000228` "no compatible drivers" | INF decorations not honored by build 26100 | Installer patches INF automatically (sections `[ATI.Mfg.NTamd64.10.0.3]` + `[ATI.Mfg.NTamd64]`) |
| Driver in store but device stays on Basic Display Adapter | Test-signed driver ranks below inbox driver | Installer falls back to `devcon update` (forced install) |
| Import fails, "file not found" (`acpcfg0001.dat`, `*.xclbin`) | Release zips not fully extracted | Extract the **complete** zips into `Drivers\Audio` / `Drivers\NPU` |
| `inf2cat` errors | Duplicate INF sections | Installer dedupes automatically; if it persists, re-download the release |
| Certificate error `0x800b0109` during install | Catalog not signed / cert missing | Installer creates the cert and re-signs all catalogs |

## Notes

- **Test signing** stays enabled - a "Test Mode" watermark may appear on the desktop.
- The Pluton null driver INF is patched the same way as the GPU INF (its HWID line lives in an `...14393` decorated section that build 26100 ignores).
- GPU driver is from **AMD Software PRO Edition** (October 2024), patched to support Server ProductType.
- Keep the "AMD Driver Test" certificate installed while using the driver - deleting it breaks catalog validation.

## Tested On

- Windows Server 2025 Standard (Build 26100)
- AMD Ryzen 7 PRO 8700GE (Phoenix, Radeon 780M)
- Hetzner bare-metal server

## License

See [LICENSE](LICENSE): the installer scripts and documentation in this repository are MIT-licensed. **All driver files** (everything under `Drivers/` and all release assets) are property of Advanced Micro Devices, Inc. / Microsoft Corporation and subject to their own license terms - they are NOT MIT and are redistributed unmodified for installation purposes only.
