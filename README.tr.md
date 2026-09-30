# AMD Phoenix Surucu Paketi - Windows Server 2025

AMD Phoenix APU'lu (Radeon 780M / 760M iGPU'li Ryzen 7000/8000 serisi) **Windows Server 2025** icin eksiksiz AMD surucu paketi (GPU + Audio + NPU).

**README dilleri:** [English (varsayilan)](README.md) | [Deutsch](README.de.md) | [Turkce](README.tr.md)

## Sorun

AMD, Phoenix (Radeon 780M) tumlesik grafigi icin Windows Server 2025'i resmi olarak desteklemiyor. Resmi surucu INF'i yalnizca `ProductType=1` (Workstation) hedefliyor; bu yuzden Windows Server (`ProductType=3`) genel "Microsoft Basic Display Adapter"a dusuyor. Audio (ACP) ve NPU aygitlari da surucusuz kaliyor.

Ayrica Server yamasinda kullanilan `NTamd64.10.0.3..16299` INF dekasyonu, Server 2025 (build 26100) tarafindan **yok sayilir** - tam donanim kimligi listelenmis olsa bile aygit "no compatible drivers" (`0xe0000228`) hatasi verir. Surucu test-imzali oldugu icin her zaman **kutuphane icindeki Basic Display Adapter'in altinda siralanir**; normal surucu secimi onu asla secmez.

## Bu Betik Ne Yapar

Kurulum programi:

1. `bcdedit /set testsigning on` ve `nointegritychecks on` etkinlestirir (yeniden baslatma gerekli)
2. Kendi imzali kod imzalama sertifikasi olusturur ("AMD Driver Test") ve Root + TrustedPublisher'a ekler
3. Gerekirse Windows SDK + WDK kurar (`signtool`, `inf2cat` ve `devcon` icin)
4. **GPU INF'ini duzgunce yamalar:**
   - Yinelenen INF bolumlerini kaldirir (onceki surumlerdeki bozuk yamaci ciktisi)
   - Build 26100'in gercekte kabul ettigi dekorasyonlar olan `[ATI.Mfg.NTamd64.10.0.3]` ve `[ATI.Mfg.NTamd64]` bolumlerini donanim kimligi listesiyle doldurur
5. **Tum** kataloglari (GPU, Audio, NPU) `inf2cat` ile yeniden olusturur ve imzalar
6. Tum suruculeri kurar; normal secim reddederse GPU icin `devcon update` ile **zorunlu kurulum** kullanir

## Iceren Suruculer

| Aygit | Donanim Kimligi | Bilesen | Surum |
|---|---|---|---|
| AMD Radeon(TM) 780M | `PCI\VEN_1002&DEV_15BF&SUBSYS_15BF1002&REV_D2` | GPU Display | 32.0.12030.9 |
| AMD Audio CoProcessor | `PCI\VEN_1022&DEV_15E2` | ACP Bus + AFD Audio | 6.0.0.100 |
| NPU Compute Accelerator | `PCI\VEN_1022&DEV_1502` | AMD NPU MCDM | 32.0.203.231 |
| Microsoft Pluton | `ACPI\MSFT0200` | Pluton Null Surucusu (opsiyonel) | 1.0.0.2 |

## Kurulum

### Hizli Kurulum

1. Repo zip'ini indirin ve cikarin (veya `git clone`)
2. **`Setup.ps1 -Download` calistirin** - surum zip'lerini indirir ve dogru `Drivers\` klasorlerine cikarir (Audio/NPU arsivi karisik dosyalar icerir ve AYRILMALIDIR - betik bunu yapar):
   ```powershell
   powershell -ExecutionPolicy Bypass -File Setup.ps1 -Download
   ```
   Zip'leri zaten indirdiyseniz betiklerin yanina koyun ve `-Download` olmadan calistirin.
3. **`Install.bat` dosyasina cift tiklayin** (otomatik yonetici ister)
4. Ilk calistirma: test signing'i acar ve **yeniden baslatma** ister
5. Yeniden baslattiktan sonra: `Install.bat`'i tekrar calistirin - tum suruculer otomatik kurulur

### Manuel Kurulum

```powershell
# Yonetici olarak calistirin
powershell -ExecutionPolicy Bypass -File Install.ps1
```

Sadece INF yamasini test edin (kurulum yok):

```powershell
powershell -ExecutionPolicy Bypass -File Install.ps1 -PatchOnly
```

## Beklenen Klasor Yapisinin Tamami icin README.md'ye bakiniz

Onemli: Release zip'lerinin **tamamini** `Drivers\` klasorlerine cikarin - eksik dosyalar kurulum basarisizligina yol acar.

## Sorun Giderme

| Belirti | Sebep | Cozum |
|---|---|---|
| `0xe0000228` "no compatible drivers" | INF dekorasyonlari build 26100 tarafindan yok sayilir | Kurulum programi INF'i otomatik yamalar (`[ATI.Mfg.NTamd64.10.0.3]` + `[ATI.Mfg.NTamd64]` bolumleri) |
| Surucu Store'da ama aygit Basic Display Adapter'da kaliyor | Test-imzali surucu kutuphane surucusunun altinda siralanir | Kurulum programi `devcon update` ile zorunlu kuruluma gecer |
| Iceaktarim hatasi, "file not found" (`acpcfg0001.dat`, `*.xclbin`) | Surum zip'leri eksik cikarildi | **Tam** zip'leri `Drivers\Audio` / `Drivers\NPU` icine cikarin |
| `inf2cat` hatalari | Yinelenmis INF bolumleri | Kurulum programi otomatik tekillestirir; surerse surumu yeniden indirin |
| Kurulumda sertifika hatasi `0x800b0109` | Katalog imzasiz / sertifika eksik | Kurulum programi sertifikayi olusturur ve tum kataloglari yeniden imzalar |

## Notlar

- **Test signing** acik kalir - masaustunde "Test Mode" filigrani gorunebilir.
- Pluton null surucu INF'i, GPU INF'i ile ayni sekilde yamalanir (HWID satiri, build 26100'un yok saydigi `...14393` dekorasyonlu bolumdedir).
- GPU surucusu **AMD Software PRO Edition**'dir (Ekim 2024), Server ProductType icin yamalanmistir.
- Surucuyu kullanirken "AMD Driver Test" sertifikasi kurulu kalmalidir - silinmesi katalog dogrulamasini bozar.

## Test Edildi

- Windows Server 2025 Standard (Build 26100)
- AMD Ryzen 7 PRO 8700GE (Phoenix, Radeon 780M)
- Hetzner bare-metal sunucu

## Lisans

Bkz. [LICENSE](LICENSE): Bu repodaki kurulum betikleri ve dokumantasyon MIT lisanslidir. **Tum surucu dosyalari** (`Drivers/` altindaki her sey ve tum surum varlklari) Advanced Micro Devices, Inc. / Microsoft Corporation'un mulkiyetindedir ve kendi lisans kosullarna tabidir - MIT DEGILDIR ve yalnzca kurulum amacyla degistirilmemis olarak yeniden dagitilir.
