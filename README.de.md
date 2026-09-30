# AMD Phoenix Treiberpaket - Windows Server 2025

Vollständiges AMD-Treiberpaket (GPU + Audio + NPU) für **Windows Server 2025** mit AMD Phoenix APUs (Ryzen 7000/8000 Serie mit Radeon 780M / 760M iGPU).

**README-Sprachen:** [English (Standard)](README.md) | [Deutsch](README.de.md) | [Turkce](README.tr.md)

## Das Problem

AMD unterstützt Windows Server 2025 für die Phoenix (Radeon 780M) integrierte Grafik offiziell nicht. Die offizielle Treiber-INF zielt nur auf `ProductType=1` (Workstation), weshalb Windows Server (`ProductType=3`) auf den generischen "Microsoft Basic Display Adapter" zurückfällt. Auch Audio (ACP) und NPU bleiben ohne Treiber.

Zusätzlich wird die INF-Dekoration `NTamd64.10.0.3..16299` vom Server-Patch **von Server 2025 (Build 26100) ignoriert** - das Gerät findet "no compatible drivers" (`0xe0000228`), obwohl die exakte Hardware-ID gelistet ist. Und da der Treiber test-signiert ist, **rangiert er immer unterhalb des vorinstallierten Basic Display Adapters** - die normale Treiberauswahl wählt ihn nie.

## Was das Skript macht

Der Installer:

1. Aktiviert `bcdedit /set testsigning on` und `nointegritychecks on` (Reboot nötig)
2. Erstellt ein selbstsigniertes Codesignatur-Zertifikat ("AMD Driver Test") und hinterlegt es in Root + TrustedPublisher
3. Installiert bei Bedarf Windows SDK + WDK (für `signtool`, `inf2cat` und `devcon`)
4. **Patcht die GPU-INF korrekt:**
   - Entfernt doppelte INF-Sektionen (fehlerhafte Patcher-Ausgabe früherer Releases)
   - Füllt die ungecappten Server-Modell-Sektionen `[ATI.Mfg.NTamd64.10.0.3]` und `[ATI.Mfg.NTamd64]` mit der Hardware-ID-Liste - das sind die Dekorationen, die Build 26100 tatsächlich akzeptiert
5. Erstellt **alle** Kataloge (GPU, Audio, NPU) mit `inf2cat` neu und signiert sie
6. Installiert alle Treiber; forciert die GPU-Installation per **`devcon update`**, falls die normale Auswahl verweigert (Ranking-Problem bei test-signierten Treibern)

## Enthaltene Treiber

| Gerät | Hardware-ID | Komponente | Version |
|---|---|---|---|
| AMD Radeon(TM) 780M | `PCI\VEN_1002&DEV_15BF&SUBSYS_15BF1002&REV_D2` | GPU Display | 32.0.12030.9 |
| AMD Audio CoProcessor | `PCI\VEN_1022&DEV_15E2` | ACP Bus + AFD Audio | 6.0.0.100 |
| NPU Compute Accelerator | `PCI\VEN_1022&DEV_1502` | AMD NPU MCDM | 32.0.203.231 |
| Microsoft Pluton | `ACPI\MSFT0200` | Pluton Null-Treiber (optional) | 1.0.0.2 |

## Installation

### Schnellinstallation

1. Repo-Zip herunterladen und entpacken (oder `git clone`)
2. **`Setup.ps1 -Download` ausführen** - lädt die Release-Zips herunter und extrahiert sie in die richtigen `Drivers\`-Ordner (das Audio/NPU-Archiv enthält gemischte Dateien und MUSS getrennt werden - das Skript macht das):
   ```powershell
   powershell -ExecutionPolicy Bypass -File Setup.ps1 -Download
   ```
   Falls `Drivers-GPU.zip` und `Drivers-Audio-NPU.zip` schon heruntergeladen sind: neben die Skripte legen und `Setup.ps1` ohne `-Download` ausführen.
3. **`Install.bat` doppelklicken** (fordert automatisch Admin-Rechte)
4. Erster Durchlauf: aktiviert Test Signing und fragt nach einem **Reboot**
5. Nach dem Reboot: `Install.bat` erneut ausführen - alle Treiber installieren sich automatisch

### Manuelle Installation

```powershell
# Als Administrator ausführen
powershell -ExecutionPolicy Bypass -File Install.ps1
```

Nur den INF-Patch testen (ohne Installation):

```powershell
powershell -ExecutionPolicy Bypass -File Install.ps1 -PatchOnly
```

## Erwartete Ordnerstruktur

```
AMD-Phoenix-Driver-WinServer2025/
|- Setup.ps1                # Laedt + extrahiert Treiber-Zips (-Download)
|- Install.bat               # Doppelklick-Installation (auto-elevate)
|- Install.ps1               # Haupt-Installer
|- README.md                 # Englisch (Standard)
|- README.de.md              # Diese Datei
|- README.tr.md              # Tuerkische Version
|- Drivers/
|  |- GPU/                   # AMD Radeon 780M Display-Treiber (~1.9 GB)
|  |  |- u0410304.inf        # AMD GPU-INF (wird zur Laufzeit gepatcht)
|  |  |- B409433/            # GPU-Binaries (DLLs, Firmware)
|  |  |- amdocl/             # OpenCL-Komponenten
|  |  |- amdfendr/           # AMD FidelityFX
|  |  |- amdfdans/           # AMD Noise Suppression
|  |  |- amdpcibridge/       # PCI-Bridge-Erweiterung
|  |  |- amdwin/             # AMD-Windows-Komponenten
|  |- Audio/                 # AMD ACP Audio (~31 MB)
|  |  |- amdacpbus.inf/.sys  # ACP-Bus-Treiber
|  |  |- amdacpafd.inf/.sys  # ACP AFD Audio-Treiber
|  |  |- acpcfg*.dat, acpimg*.dat
|  |  |- amdacpbusext/       # ACP-Bus-Erweiterung (CopyINF-Subpaket)
|  |- NPU/                   # AMD NPU (~228 MB)
|  |  |- kipudrv.inf         # NPU Compute Accelerator
|  |  |- ipustack.sys        # NPU-Kerneltreiber
|  |  |- *.xclbin, RadeonML*.dll, xrt*.dll, ...
|  |- Pluton/                # Microsoft Pluton Null-Treiber (~17 KB)
|     |- plutonnull.inf
```

## Fehlerbehebung

| Symptom | Ursache | Lösung |
|---|---|---|
| `0xe0000228` "no compatible drivers" | INF-Dekorationen werden von Build 26100 ignoriert | Installer patcht die INF automatisch (Sektionen `[ATI.Mfg.NTamd64.10.0.3]` + `[ATI.Mfg.NTamd64]`) |
| Treiber im Store, Gerät bleibt am Basic Display Adapter | Test-signierter Treiber rangiert unterhalb des Inbox-Treibers | Installer faellt auf `devcon update` zurück (erzwungene Installation) |
| Import-Feher, "file not found" (`acpcfg0001.dat`, `*.xclbin`) | Release-Zips unvollstaendig extrahiert | Die **kompletten** Zips nach `Drivers\Audio` / `Drivers\NPU` extrahieren |
| `inf2cat`-Fehler | Doppelte INF-Sektionen | Installer dedupliziert automatisch; sonst Release neu laden |
| Zertifikatsfehler `0x800b0109` bei der Installation | Katalog unsigniert / Zertifikat fehlt | Installer erstellt das Zertifikat und signiert alle Kataloge neu |

## Hinweise

- **Test Signing** bleibt aktiviert - auf dem Desktop kann ein "Test Mode"-Wasserzeichen erscheinen.
- Die Pluton-Null-Treiber-INF wird analog zur GPU-INF gepatcht (die HWID-Zeile steckt in einer `...14393`-Dekorierten Sektion, die Build 26100 ignoriert).
- GPU-Treiber aus der **AMD Software PRO Edition** (Oktober 2024), gepatcht für Server ProductType.
- Das Zertifikat "AMD Driver Test" muss installiert bleiben, solange der Treiber genutzt wird - Loeschen bricht die Katalog-Validierung.

## Getestet auf

- Windows Server 2025 Standard (Build 26100)
- AMD Ryzen 7 PRO 8700GE (Phoenix, Radeon 780M)
- Hetzner Bare-Metal-Server

## Lizenz

Siehe [LICENSE](LICENSE): Die Installer-Skripte und die Dokumentation in diesem Repo stehen unter MIT. **Alle Treiberdateien** (alles unter `Drivers/` und sämtliche Release-Assets) gehören Advanced Micro Devices, Inc. / Microsoft Corporation und unterliegen deren eigenen Lizenzbedingungen - sie sind NICHT MIT und werden unverändert ausschließlich zu Installationszwecken weiterverbreitet.
