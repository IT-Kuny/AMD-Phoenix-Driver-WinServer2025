# AMD Phoenix Driver Pack - Windows Server 2025

Complete AMD driver package (GPU + Audio + NPU) for **Windows Server 2025** with AMD Phoenix APU.

## Problem

AMD does not officially support Windows Server 2025 for the Phoenix (Radeon 780M) integrated GPU. The official driver INF only targets `ProductType=1` (Workstation), causing Windows Server (`ProductType=3`) to fall back to the generic "Microsoft Basic Display Adapter". Audio and NPU devices also remain without drivers.

## What This Does

This installer automatically:
- Patches the AMD GPU driver INF to add **Windows Server support** (`NTamd64.10.0.3..16299` sections)
- Creates a self-signed certificate and signs the driver catalog
- Automatically installs **Windows SDK + WDK** if needed (for `signtool` and `inf2cat`)
- Installs **all** AMD drivers: GPU, Audio, NPU, and Pluton

## Included Drivers

| Device | Hardware ID | Driver | Version |
|---|---|---|---|
| AMD Radeon(TM) 780M | `PCI\VEN_1002&DEV_15BF&SUBSYS_15BF1002&REV_D2` | GPU Display | 32.0.12030.9 |
| AMD Audio CoProcessor | `PCI\VEN_1022&DEV_15E2` | ACP Bus + AFD Audio | 6.0.0.100 |
| NPU Compute Accelerator | `PCI\VEN_1022&DEV_1502` | AMD NPU MCDM | 32.0.203.231 |
| Microsoft Pluton | `ACPI\MSFT0200` | Pluton Null Driver | 1.0.0.2 |

## Installation

### Quick Install

1. Download **all zip files** from the [latest release](../../releases/latest)
2. Extract them so the folder structure looks like below
3. **Double-click `Install.bat`** (auto-elevates to admin)
4. First run: will enable test signing and **reboot**
5. After reboot: run `Install.bat` again → all drivers install automatically

### Manual Install

```powershell
# Run as Administrator
powershell -ExecutionPolicy Bypass -File Install.ps1
```

## What the Installer Does (Step by Step)

1. Enables `bcdedit /set testsigning on` and `nointegritychecks on`
2. Creates a self-signed code signing certificate ("AMD Driver Test")
3. Installs Windows SDK (signtool) and WDK (inf2cat) via `winget`
4. Generates driver catalog with `inf2cat`
5. Signs all catalog files with the self-signed certificate
6. Installs **GPU driver** → AMD Radeon(TM) 780M
7. Installs **Audio drivers** → AMD ACP Bus + AFD
8. Installs **NPU driver** → AMD Compute Accelerator
9. Installs **Pluton null driver** (optional, may not work on Server)

## Requirements

- **Windows Server 2025** (Build 26100)
- AMD Phoenix APU (Radeon 780M / 760M)
- Administrator privileges
- Internet connection (first run only - for SDK/WDK download)
- `winget` package manager

## Expected Folder Structure

```
AMD_Phoenix_Setup/
├── Install.bat              # Double-click to install (auto-elevates)
├── Install.ps1              # Main installer script
├── README.md
└── Drivers/
    ├── GPU/                 # AMD Radeon 780M display driver (~1.9 GB)
    │   ├── u0410304.inf     # Patched INF with Server support
    │   ├── B409433/         # GPU driver binaries (DLLs, firmware)
    │   ├── amdocl/          # OpenCL components
    │   ├── amdfendr/        # AMD FidelityFX
    │   ├── amdfdans/        # AMD noise suppression
    │   ├── amdpcibridge/    # PCI bridge extension
    │   └── amdwin/          # AMD Windows components
    ├── Audio/               # AMD ACP Audio drivers (~31 MB)
    │   ├── amdacpbus.inf    # ACP Bus driver
    │   ├── amdacpafd.inf    # ACP AFD audio driver
    │   └── ...
    ├── NPU/                 # AMD NPU/PSP driver (~228 MB)
    │   ├── kipudrv.inf      # NPU compute accelerator
    │   └── ...
    └── Pluton/              # Microsoft Pluton null driver (~17 KB)
        └── plutonnull.inf
```

## Notes

- **Test signing** will be enabled. A "Test Mode" watermark may appear on the desktop.
- The `ACPI\MSFT0200` (Microsoft Pluton) device may remain with an error on Server — this is expected and non-critical.
- GPU driver is from **AMD Software PRO Edition** (October 2024), patched to support Server ProductType.
- Audio and NPU drivers are **officially signed by Microsoft WHCP** — no patching needed for those.

## Tested On

- Windows Server 2025 Standard (Build 26100)
- AMD Phoenix APU with Radeon 780M integrated graphics
- Hetzner bare-metal server

## License

The installer scripts are provided as-is under MIT. AMD driver files are property of Advanced Micro Devices, Inc. and subject to AMD's license terms.
