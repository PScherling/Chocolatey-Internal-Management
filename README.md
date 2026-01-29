![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue)
![Platform](https://img.shields.io/badge/Platform-Windows-blue)
![Audience](https://img.shields.io/badge/Audience-Enterprise-informational)
![Maintenance](https://img.shields.io/badge/Maintained-Yes-success)

# Chocolatey-Internal-Offline-Management

A PowerShell toolkit to **create and maintain internal/offline Chocolatey packages** backed by **ProGet**.
I Started this project in case the "Chocolatey for Busniess" solution is not applicable for you and you can only use the "FOSS" variant of Chocolatey.

This repository focuses on a practical enterprise workflow:

- **Installer binaries** (EXE/MSI/MSU/APPX/MSIX/APPXBUNDLE/MSIXBUNDLE) are stored in a **ProGet Asset Directory**
- **Chocolatey packages** reference internal ProGet URLs and validate with **SHA256**
- Packages are **packed and pushed** to a **ProGet NuGet (Chocolatey) feed**
- Clients install from your internal feed (no public internet dependency)

 ### Disclamer
 The whole Toolkit is intended for internal feed ONLY usage. Never use this to push packages to public repositories!

---

## Why this exists

Chocolatey is great at client-side package install/uninstall, but in locked-down environments you still need:

- a consistent naming convention for installers
- a binary host (ProGet Assets) + package host (ProGet NuGet feed)
- repeatable creation of new packages
- repeatable update workflow (detect new version → download → upload → update nuspec/install script/checksums → push)

This toolkit automates those steps.

---

## What’s included

### 1) `CreateNewChocoPackage.ps1`
Automates the initial creation of an internal Chocolatey package:

- creates vendor base directory structure
- generates a package template via `choco new`
- copies and renames the installer to a standard naming convention  
  `SoftwareName_Arch_Version.FileType`
- calculates SHA256
- updates `tools\chocolateyinstall.ps1`:
  - sets `$url` / `$url64` to ProGet Asset URL
  - updates `fileType`, `checksum`, `checksum64`, `checksumType*`
- packs `.nupkg` and pushes it to ProGet feed

### 2) `UpdateSoftwarePackages.ps1`
Automates updating existing packages based on the 'SoftwareList.csv':

- reads `SoftwareList.csv`
- checks latest versions via:
  - **API**: WinGet manifests through GitHub API (+ YAML parsing)
  - **WEB**: vendor URL defined in CSV
  - **LOCAL**: pre-downloaded files in a local drop location
- downloads the new installer
- uploads it to ProGet Assets
- fetches SHA256 from ProGet metadata
- updates:
  - `.nuspec` version
  - `tools\checksums.json`
  - `tools\chocolateyinstall.ps1` (urls/fileType/checksums)
- packs and pushes updated `.nupkg` to ProGet feed
- writes detailed logs + warning/error summary

<img width="1579" height="843" alt="image" src="https://github.com/user-attachments/assets/4bc45d5c-922d-4839-84a2-493a2620f027" />
<img width="1579" height="843" alt="image" src="https://github.com/user-attachments/assets/f4dce42d-1074-45e2-aa4e-cd1193fddaba" />
<img width="1579" height="843" alt="image" src="https://github.com/user-attachments/assets/40e12f7a-8678-4ef9-afad-c4e3228adda2" />

---

## Requirements

### General
- Windows
- PowerShell **5.1+** (PowerShell 7+ recommended)
- Chocolatey CLI installed on the packaging host
- ProGet server (Free or paid)

### For WinGet API mode
- GitHub personal access token (PAT) recommended (avoids rate limits)
- PowerShell module: `powershell-yaml` (script can auto-install/import)

### ProGet
You need two ProGet “areas”:
1) **Asset Directory** (installer binaries)  
2) **NuGet Feed** (Chocolatey packages)  

And two API keys:
- **Asset API key**: View/Download (+ Add if uploading)
- **Feed API key**: Publish (push) permission to the NuGet feed

---

## ProGet setup (high level)

1) Create an **Asset Directory** (example name: `choco-assets`)
2) Create a **NuGet feed** for Chocolatey packages (example name: `internal-choco`)
3) Generate API keys:
   - one for assets
   - one for feed publishing
4) Verify endpoints:
   - Asset download/content URL pattern:
     - `http(s)://<server>:<port>/endpoints/<assetDir>/content/<path>/<file>`
   - Asset metadata URL pattern:
     - `http(s)://<server>:<port>/endpoints/<assetDir>/metadata/<path>/<file>`
   - Asset dir listing URL pattern:
     - `http(s)://<server>:<port>/endpoints/<assetDir>/dir/<path>`
   - NuGet feed push endpoint used by `choco push`:
     - `http(s)://<server>:<port>/nuget/<feedName>/`

For more information how to setup ProGet with Chocolatey visit: 
- https://docs.inedo.com/docs/proget/overview
- https://docs.chocolatey.org/en-us/features/host-packages/

---

## Supported installer types

These values are supported by the toolkit for **naming, storage, and metadata**:

- `exe`
- `msi`
- `msu`
- `appx`
- `msix`
- `appxbundle`
- `msixbundle`

> Note: **Chocolatey helper functions** are primarily designed around `exe/msi/msu`.  
> APPX/MSIX often require custom install logic (`Add-AppxPackage`, provisioning, certificates, etc.).  
> This toolkit can still **package and update** those installers, but your `chocolateyinstall.ps1` template may need to be adjusted for those types.

---

## Quick start

### 1) Create a new Chocolatey package

```powershell
.\scripts\CreateNewChocoPackage.ps1 `
  -ChocoPackagesPath "E:\Choco\Packages" `
  -SourceFilePath "C:\Users\Admin\Downloads" `
  -SourceFile "WinSCP.exe" `
  -Publisher "WinSCP" `
  -SoftwareName "WinSCP" `
  -Arch "x86" `
  -Version "6.6.0" `
  -FileType "exe" `
  -Protocol "http" `
  -ProGetSrv "PSC-SWREPO1" `
  -ProGetPort "8624" `
  -AssetName "choco-assets" `
  -FeedName "internal-choco" `
  -ProGetFeedKey "YOUR_FEED_API_KEY"
```

What happens next:
- installer is copied into `tools\`
- renamed to `Software_Arch_Version.ext`
- install script updated to reference ProGet Asset URL + SHA256
- you’re prompted to review `silentArgs` + `.nuspec`
- package is built and pushed to ProGet

---

### 2) Update packages automatically (WinGet API mode)

```powershell
.\scripts\UpdateSoftwarePackages.ps1 `
  -UpdateOption "API" `
  -GitToken "YOUR_GITHUB_TOKEN" `
  -ProGetFeedApiKey "YOUR_FEED_API_KEY" `
  -ProGetAssetApiKey "YOUR_ASSET_API_KEY" `
  -ProGetBaseUrl "http://PSC-SWREPO1:8624" `
  -ProGetAssetDir "choco-assets" `
  -ProGetChocoFeedName "internal-choco" `
  -ChocoPackageSourceRoot "E:\Choco\Packages"
```

---

## Configuration

### `SoftwareList.csv`

Delimiter: `;`

Recommended columns:

| Column | Example | Notes |
|---|---|---|
| Publisher | `NotepadPlusPlus` | Used for folder structure and winget path |
| SoftwareName | `NotepadPlusPlus` | Package name and winget path |
| SubName1 | *(optional)* | Used for deeper winget manifest folders / naming |
| SubName2 | *(optional)* | Same as above |
| PreferredExtension | `exe` | Preferred installer type (or file extension fallback) |
| Arch | `x64` or `x86` | Used to pick installer in YAML |
| UpdateOption | `API`, `WEB`, `LOCAL` | How the script updates this package |
| WebLink | `https://...` | Required for WEB mode |

Example `SoftwareList.csv`:

```csv
Publisher;SoftwareName;SubName1;SubName2;PreferredExtension;Arch;UpdateOption;WebLink
NotepadPlusPlus;NotepadPlusPlus;;;exe;x64;API;
WinSCP;WinSCP;;;exe;x86;API;
VendorX;MyApp;;;msi;x64;WEB;https://vendor.example.com/download
LocalVendor;ToolX;;;exe;x64;LOCAL;
```

---

## Client usage (example)

On clients, configure Chocolatey to use your internal feed:

```powershell
choco source add -n=internal-choco -s "http://PSC-SWREPO1:8624/nuget/internal-choco/"
choco source disable -n=chocolatey
choco install winscp -y
```

*(Adapt names/URLs to your environment and policies.)*

---

## Security notes

- **Do not commit** API keys or tokens to GitHub
- Prefer:
  - environment variables
  - secure secrets store (Credential Manager / vault)
  - prompted input (your update script already supports prompting)
- Treat ProGet asset/feed keys as secrets with least privilege:
  - assets: view/download + upload only if needed
  - feed: publish only

---

## Troubleshooting (common)

### 401 / 403 from ProGet endpoints
- Verify you are using the right API key for the right endpoint:
  - **Asset endpoints** require the **asset API key**
  - **Feed push** requires the **feed API key**
- Verify permissions assigned to key in ProGet

### YAML parsing fails
- Ensure `powershell-yaml` is installed/imported
- WinGet manifests can change structure; update matching logic if needed

### URL replacement does not update `$url` / `$url64`
- Ensure the template contains a line like:
  - `$url64 = '...'`
  - `$url = '...'`
- Ensure the variable name matches your script (`url64` vs `url64bit` are different)

### APPX/MSIX install failures
- You may need:
  - `Add-AppxPackage` instead of Chocolatey install helper functions
  - certificate trust chain installed
  - provisioning for all users (`Add-AppxProvisionedPackage`)
  - correct file path handling (avoid invalid path characters)

---

## Roadmap ideas

- Add switch: `-EmbedInstaller` vs `-UseProGetUrl`
- Add templating:
  - separate install script templates per installer type
- Add uninstall support for APPX/MSIX (where applicable)

---

## Contributing

PRs and issues are welcome. Please include:
- the smallest reproducible scenario
- relevant log snippet (remove secrets!)
- expected vs actual result

---

## 👤 Author

**Author:** Patrick Scherling  
**Contact:** @Patrick Scherling  

---

> ⚡ *“Automate. Standardize. Simplify.”*  
> Part of Patrick Scherling’s IT automation suite for modern Windows Server infrastructure management.
