# AMD Phoenix GPU Driver - Windows Server 2025

Patched AMD Radeon 780M (Phoenix) GPU driver installer for **Windows Server 2025**.

## Problem

AMD does not officially support Windows Server 2025 for the Phoenix (Radeon 780M) integrated GPU. The official driver INF only targets `ProductType=1` (Workstation), causing Windows Server (`ProductType=3`) to fall back to the generic "Microsoft Basic Display Adapter".

## What This Does

- Patches the AMD driver INF to add **Windows Server support** (`NTamd64.10.0.3..16299` sections)
- Creates a self-signed certificate and signs the driver catalog
- Automatically installs **Windows SDK + WDK** if needed (for `signtool` and `inf2cat`)
- Installs the GPU driver + AMD Audio (ACP) + AMD NPU drivers

## Supported Hardware

| Device | Hardware ID | Driver |
|---|---|---|
| AMD Radeon(TM) 780M | `PCI\VEN_1002&DEV_15BF&SUBSYS_15BF1002&REV_D2` | GPU Display |
| AMD Audio CoProcessor | `PCI\VEN_1022&DEV_15E2` | ACP Bus Audio |
| NPU Compute Accelerator | `PCI\VEN_1022&DEV_1502` | AMD NPU MCDM |

## Installation

### Quick Install

1. Download the latest release (includes driver files)
2. Extract to a folder
3. **Double-click `Install.bat`** or run `AMD_Phoenix_Installer.exe`
4. First run: will enable test signing and ask for reboot
5. After reboot: run again to install all drivers

### Manual Install

```powershell
# Run as Administrator
powershell -ExecutionPolicy Bypass -File Install.ps1
```

## What the Installer Does (Step by Step)

1. Enables `bcdedit /set testsigning on` and `nointegritychecks on`
2. Creates a self-signed code signing certificate ("AMD Driver Test")
3. Installs Windows SDK (signtool) and WDK (inf2cat) via winget
4. Generates driver catalog with `inf2cat`
5. Signs the catalog with the self-signed certificate
6. Installs GPU, Audio, and NPU drivers via `pnputil`

## Requirements

- Windows Server 2025 (Build 26100)
- AMD Phoenix APU (Radeon 780M / 760M)
- Administrator privileges
- Internet connection (for SDK/WDK download on first run)
- `winget` package manager

## Notes

- **Test signing** will be enabled. A "Test Mode" watermark may appear on the desktop.
- The `ACPI\MSFT0200` (Microsoft Pluton) device may remain with an error - this is normal on Server.
- Driver version: **32.0.12030.9** (AMD Software PRO Edition, October 2024)

## File Structure

```
AMD_Phoenix_Setup/
├── Install.bat                  # Double-click launcher (auto-elevates to admin)
├── Install.ps1                  # Main installer script
├── README.md
└── Drivers/
    ├── GPU/                     # AMD Radeon 780M display driver (~1.9 GB)
    │   ├── u0410304.inf         # Patched INF with Server support
    │   └── B409433/             # Driver binaries
    ├── Audio/                   # AMD ACP Audio driver (~31 MB)
    ├── NPU/                     # AMD NPU/PSP driver (~228 MB)
    └── Pluton/                  # Microsoft Pluton null driver
```

## License

The installer scripts are provided as-is. AMD driver files are property of AMD and subject to AMD's license terms.
