![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue)
![Platform](https://img.shields.io/badge/Platform-Windows-blue)
![Repository](https://img.shields.io/badge/ProGet-Free%20%7C%20Paid-informational)
![Chocolatey](https://img.shields.io/badge/Chocolatey-FOSS%20%7C%20C4B-informational)
![Audience](https://img.shields.io/badge/Audience-Enterprise%20%7C%20SelfHosting-informational)
![Maintenance](https://img.shields.io/badge/Maintained-Yes-success)

# Chocolatey Internal Management Toolkit (ProGet) - Pre-Release

A PowerShell-first toolkit to **create, update, and deploy** Chocolatey packages in **self-hosted / offline-friendly** environments using **ProGet** as:

- **Asset host** (installer binaries, large artifacts)
- **NuGet feed** (Chocolatey packages)

No Otter, no Maven, no extra deployment suites required — **just PowerShell + cmd + ProGet + Chocolatey**.

> **Disclaimer**
> - This toolkit is intended for **internal repository usage only**.
> - **Do not** use this to publish packages to public repositories.
> - **Do not commit API keys / PATs**. Use prompts, environment variables, or a secure secret store.

---

## Why this exists

Chocolatey is great for client-side install/uninstall. But in restricted enterprise networks you still need:

- A consistent naming convention for installers and packages
- A binary host (**ProGet Assets**) + package host (**ProGet NuGet feed**)
- Repeatable package creation (new software)
- Repeatable update workflow (discover → download → upload → update package → push)

This repository automates the full workflow for both **Chocolatey FOSS** and **Chocolatey for Business (C4B)** environments.

---

## High-level architecture

```
             (Packaging Host)
      +-----------------------------+
      | CreateNewChocoPackage.ps1   |
      | UpdateSoftwarePackages.ps1  |
      +--------------+--------------+
                     |
                     | upload installers / push packages
                     v
           +---------+---------+
           |      ProGet       |
           |  Asset Directory  |  <-- installers, zips, msix, etc.
           |  NuGet Feed       |  <-- .nupkg packages
           +---------+---------+
                     |
                     | internal feed + trusted cert
                     v
      +-----------------------------+
      |        Client(s)            |
      | choco install <pkg>         |
      | MDT task sequence installs  |
      +-----------------------------+
```

---

## Repository contents

This project has two “sides”:

### A) Managing (Packaging + Updating)
- `launcher.bat`  
  A simple launcher to select bewteen 'Create a new package' or 'Update software packages'. You can create a nice desktop shortcut to use this batch script ;)
- `CreateNewChocoPackage.ps1`  
  Creates a new internal Chocolatey package template, updates the install script to point to a ProGet Asset URL (including SHA256), builds the .nupkg and pushes it to a ProGet Chocolatey/NuGet feed.
- `UpdateSoftwarePackages.ps1`  
  Automates downloading, updating, and synchronizing third-party software installers from multiple sources (Winget API, direct web links, or local downloads).
- `UpdateMSOffice.ps1` *(helper script for Office CDN/ODT updates)*  
  Automates downloading and updating of Microsoft Office installation sources for multiple editions using the Office Deployment Tool (ODT).
- `SoftwareList.csv`  
  'Database' of your used/managed software in your environment

### B) Installation (Client / Deployment)
- `Chocolatey-AutoInstall.ps1`  
  Installs Chocolatey CLI **offline-friendly** from a local/internal `.nupkg`, can configure internal feed + trust certificate.
- `CreateSelfSignedCert.ps1`  
  Creates a self-signed TLS cert for C4B/CCM servers and exports `.pfx` + `.cer`.
- `Chocolatey-AgentSetup.ps1`  
  Installs/configures Chocolatey Agent for C4B + CCM.
- `C4B-AutoInstall.ps1`  
  Automated C4B + CCM + ProGet setup (incl. SQL Express backend for CCM).
- `Install_ChocoApplication.ps1`  
  MDT task sequence helper to install packages silently during deployment.

> Tip: Many teams keep “Managing” scripts on a packaging server and “Installation” scripts in deployment shares / client automation repos.

---

## Requirements

### General
- Windows
- PowerShell **5.1+** (PowerShell 7+ recommended)
- ProGet (Free or paid)
- Chocolatey CLI installed on the packaging host (for `choco new`, `choco pack`, `choco push`)

### For update providers
- **Winget/GitHub API**:
  - GitHub Personal Access Token (PAT) recommended (avoids rate limits)
  - `powershell-yaml` module (auto-install/import supported)
- **WebDirectory/DirectUrl**:
  - HTTPS/HTTP access to vendor endpoints or internal endpoints
- **Local**:
  - A local “drop” folder with manually downloaded installers

### ProGet
You typically use:
1) **Asset Directory** (installer binaries / zips)  
2) **NuGet feed** (Chocolatey packages)

And two API keys:
- **Asset API key**: View/Download (+ Add if uploading)
- **Feed API key**: Publish permission for NuGet feed (`choco push`)

---

## ProGet setup (high level)

1) Create an **Asset Directory** (example: `choco-assets`)
2) Create a **NuGet feed** for Chocolatey packages (example: `choco-production`)
3) Create API keys:
   - one for assets (upload + view)
   - one for feed publishing (push)
4) Verify endpoint patterns:

- Asset content download/upload:
  - `http(s)://<server>:<port>/endpoints/<assetDir>/content/<path>/<file>`
- Asset metadata:
  - `http(s)://<server>:<port>/endpoints/<assetDir>/metadata/<path>/<file>`
- Asset directory listing:
  - `http(s)://<server>:<port>/endpoints/<assetDir>/dir/<path>`
- NuGet feed push endpoint (used by `choco push`):
  - `http(s)://<server>:<port>/nuget/<feedName>/`

References:
- ProGet docs: https://docs.inedo.com/docs/proget/overview
- Chocolatey hosting packages: https://docs.chocolatey.org/en-us/features/host-packages/

---

## Supported artifact types

The toolkit can handle artifacts used as “installers” or payloads (stored in ProGet assets):

- `exe`, `msi`, `msu`
- `appx`, `msix`, `appxbundle`, `msixbundle`
- `zip`
- `nupkg`

> Note: Chocolatey helper functions are most straightforward for `exe/msi/msu`.
> APPX/MSIX often need custom install logic and certificate handling.

---

## Quick start

### 1) Create a new internal Chocolatey package

```powershell
.\CreateNewChocoPackage.ps1 `
  -ChocoPackagesPath "E:\Choco\Packages" `
  -SourceFilePath "C:\Users\Admin\Downloads" `
  -SourceFile "WinSCP.exe" `
  -Publisher "WinSCP" `
  -SoftwareName "WinSCP" `
  -Arch "x86" `
  -Version "6.6.0" `
  -FileType "exe" `
  -Protocol "https" `
  -ServerFqdn "PSC-SWREPO1" `
  -ProGetPort "8625" `
  -AssetName "choco-assets" `
  -FeedName "choco-production" `
  -ProGetFeedKey "YOUR_FEED_API_KEY"
```

What it does (typical):
- Creates vendor/software folder structure
- Generates template (`choco new`)
- Copies + renames installer into `tools\` using a deterministic format:
  - `SoftwareName[_SubName1][_SubName2]_Arch_Version.ext`
- Updates `tools\chocolateyinstall.ps1` (`$url/$url64`, `fileType`, SHA256)
- Packs and pushes to ProGet feed

### 2) Update packages automatically

Example: **API mode** (Winget/GitHub manifests)

```powershell
.\UpdateSoftwarePackages.ps1 `
  -UpdateOption API `
  -GitToken "YOUR_GITHUB_TOKEN" `
  -ProGetFeedApiKey "YOUR_FEED_API_KEY" `
  -ProGetAssetApiKey "YOUR_ASSET_API_KEY" `
  -ProGetBaseUrl "https://psc-swrepo1.local:8625" `
  -ProGetAssetDir "choco-assets" `
  -ProGetChocoFeedName "choco-production" `
  -ChocoPackageSourceRoot "E:\Choco\Packages"
```

Test mode (skip upload/push):
```powershell
.\UpdateSoftwarePackages.ps1 -UpdateOption API ... -WhatIfPublish
```

Force mode (run pipeline even if versions match):
```powershell
.\UpdateSoftwarePackages.ps1 -UpdateOption API ... -Force
```
<img width="1676" height="835" alt="API_1" src="https://github.com/user-attachments/assets/4b053b47-462b-45aa-9205-b32268f2717a" />
<img width="1676" height="835" alt="API_2" src="https://github.com/user-attachments/assets/b223a4a2-7c4a-4998-8494-71431fc96902" />
<img width="1676" height="835" alt="API_3" src="https://github.com/user-attachments/assets/30abd4b5-b4f7-424d-b02e-ebcbacb67d9f" />
<img width="1676" height="835" alt="API_4" src="https://github.com/user-attachments/assets/17458da0-e7b5-48f3-abf7-ea74cb5eb739" />
<img width="1676" height="835" alt="API_5" src="https://github.com/user-attachments/assets/dd237a63-7d3b-42cc-9a2c-807b502d10d8" />


---

## Configuration: `SoftwareList.csv`

Delimiter: `;`

### Recommended columns (current model)
| Column | Example | Meaning |
|---|---|---|
| Publisher | `Chocolatey` | Folder grouping + display |
| SoftwareName | `ChocolateyGUI` | Base name used for package/folder |
| SubName1 | `ProPlus` | Optional specialization / edition |
| SubName2 | *(empty)* | Optional second specialization |
| PreferredExtension | `.msi` | Enterprise-controlled ext used for naming + selection |
| Arch | `x64` / `x86` | Target architecture |
| UpdateOption | `API` / `WEB` / `LOCAL` / `ALL` | Run mode selection |
| SourceType | `Winget` / `GitHubRelease` / `WebDirectory` / `DirectUrl` / `Local` / `OfficeCdn` | Provider |
| SourceRef | `chocolatey/ChocolateyGUI` | Provider-specific reference |
| ManifestSubPath | *(optional)* | Winget manifest subpath override |
| AssetPattern | `.*x64.*\.msi$` | Regex to select correct GitHub release asset |
| ManualVersionRequired | `True/False` | Force prompt for version in LOCAL mode |
| Notes | *(optional)* | Documentation / vendor URL etc. |

### Examples

**Winget**
```csv
7zip;7zip;;; .msi;x64;API;Winget;7zip.7zip;;;;
```

**GitHubRelease**
```csv
Chocolatey;ChocolateyGUI;;; .msi;x64;API;GitHubRelease;chocolatey/ChocolateyGUI;;.*x64.*\.msi$;;
```

**WebDirectory**
```csv
VMware;VMwareTools;;; .exe;x64;WEB;WebDirectory;https://packages.vmware.com/tools/esx/latest/windows/x64/;;.*\.exe$;;
```

**DirectUrl**
```csv
Chocolatey;Chocolatey;;; .nupkg;x64;WEB;DirectUrl;https://community.chocolatey.org/api/v2/package/chocolatey;;;;
```

**Local**
```csv
AMD;Adrenalin;;; .exe;x64;LOCAL;Local;;;;True;https://www.amd.com/...
```

**Office CDN (handled via UpdateMSOffice helper)**
```csv
Microsoft;OfficeLTSC2021;ProPlus;;.exe;x64;LOCAL;OfficeCdn;Microsoft.Office.LTSC.2021.ProPlus;;;False;
Microsoft;OfficeLTSC2021;Standard;;.exe;x64;LOCAL;OfficeCdn;Microsoft.Office.LTSC.2021.Standard;;;False;
```

---

## MS Office handling (ODT / CDN)

Modern Office editions require the ODT/CDN approach. This repo supports Office updates by:

1) Running `UpdateMSOffice.ps1` to refresh Office content
2) Packaging the refreshed content into a ZIP (large files)
3) Uploading ZIP to ProGet Assets and updating the Chocolatey package to reference it

### Office version tracking
Office packages use a `tools\version.json` (inside the package source folder) to determine whether a new Office build exists.

This keeps Office versioning independent from ProGet asset naming or nuspec alone.

---

## Large assets (2GB+) upload note

Some Office ZIPs exceed 2GB. For these, the ProGet upload logic uses **.NET HttpClient streaming** to avoid PowerShell memory limits and to achieve good performance.

If you see errors like:
- `ReadAllBytes ... file is too long ... <2GB limit`
- `Compress-Archive ... Stream was too long`

Use:
- HttpClient streaming for upload
- 7-Zip for creating large archives

---

## Client usage (internal feed example)

```powershell
choco source add -n=internal -s "https://psc-swrepo1.local:8625/nuget/choco-production/"
choco source disable -n=chocolatey
choco install winscp -y
```

> If your ProGet uses a self-signed certificate, deploy the `.cer` to clients (Trusted Root) or use the helper scripts in this repo.

---

## Launchers

### Managing launcher
`launcher.bat` provides a menu to:
- Create new package
- Update packages (ALL/API/WEB/LOCAL)
<img width="1113" height="626" alt="launcher" src="https://github.com/user-attachments/assets/dd23a812-44ec-44aa-902f-07838eb39735" />


### Installation launcher (planned)
A second launcher that provides:
- Chocolatey offline bootstrap
- Agent/CCM setup
- Certificate creation/import
- MDT install helpers
<img width="1113" height="626" alt="image" src="https://github.com/user-attachments/assets/72076459-6d37-46af-8929-a33b2314a4ca" />

---

## Security guidance

- Never hardcode or commit:
  - ProGet API keys
  - GitHub PATs
  - SQL passwords
- Prefer:
  - Prompted input
  - Environment variables
  - Credential Manager / vault solutions
- Use least privilege:
  - Asset key: upload/download only
  - Feed key: push only

---

## Troubleshooting

### 401 / 403 from ProGet endpoints
- Confirm you used the right key for the right endpoint:
  - Asset endpoints use **Asset API key**
  - Feed push uses **Feed API key**
- Check permissions assigned in ProGet

### GitHubRelease “No asset matched pattern”
- Confirm `AssetPattern` matches actual release asset names
- Log available assets and refine regex (recommended)

### LOCAL mode picks the wrong file
- Ensure the file is actually present in the drop directory
- Use `ManualVersionRequired=True` when version cannot be read
- Use `SourceRef` as an additional hint (product key / expected string)

### Office ZIP creation fails with “Stream was too long”
- Use 7-Zip for archive creation instead of `Compress-Archive`

---

## Roadmap

- Add optional `SpecialHandling` column (future)
- Improve templating per installer type (exe/msi/msu/msix/appx/zip)
- Optional “assets-only mode” for teams using ProGet without Chocolatey packaging
- Richer client bootstrap menu launcher

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

