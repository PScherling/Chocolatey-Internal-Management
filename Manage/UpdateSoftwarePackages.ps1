<#
.SYNOPSIS
	Automates downloading, updating, and synchronizing third-party software installers from multiple sources (Winget API, direct web links, or local downloads).
.DESCRIPTION
    The **UpdateSoftwarePackages.ps1** script is an advanced automation tool designed to maintain up-to-date software packages
	for enterprise deployment environments build with Chocolatey and ProGet. 
	It dynamically checks for new software versions, downloads the latest installers, and synchronizes them across local package directories and repository shares.
	
	It supports three main update modes:
	- **API Mode:** Uses the official Microsoft WinGet GitHub repository to query and fetch installers via the GitHub API.
	- **WEB Mode:** Downloads installers directly from vendor websites using static links defined in a CSV file.
	- **LOCAL Mode:** Imports pre-downloaded installers from a designated local directory for manual updates or offline maintenance.
	
	The script reads from a structured CSV file (`SoftwareList.csv`) defining each software package's publisher, name, architecture, update method, and file preferences.  
	It automatically detects changes, replaces old installers, logs all actions, and provides error and warning summaries.
	
	Features:
	- Modular structure with dynamic mode selection (API / WEB / LOCAL / ALL)
	- Integration with GitHub API for WinGet manifest parsing and version checks
	- YAML parsing via `powershell-yaml` module (automatically installed if missing)
	- Automatic handling of nested installers and fallback download mechanisms
	- Logging of all progress, warnings, and errors to `.\Logs\UpdateSoftwarePackages`
	- Interactive and color-coded PowerShell console interface
	- File synchronization to both local storage and ProGet Repository
	
	This script is particularly useful for:
	- Deployment administrators managing large software libraries
	- Automated update maintenance of application repositories
	- Enterprise software packaging and version management

.PARAMETER UpdateOption
    Specifies which update method to use: ALL, API, WEB, or LOCAL. Default is ALL.

.PARAMETER GitToken
    GitHub Personal Access Token for accessing the WinGet repository API.

.PARAMETER ProGetFeedApiKey
    API Key for accessing the ProGet feed where Chocolatey packages are hosted. 

.PARAMETER ProGetAssetApiKey
    API Key for accessing the ProGet asset repository where installer files are stored.

.PARAMETER ProGetBaseUrl
    Base URL of the ProGet server including the specified port (e.g., http://PSC-SWREPO1:8624).

.PARAMETER ProGetAssetDir
    Name of the ProGet asset directory (e.g., choco-assets).   

.PARAMETER ProGetChocoFeedName
    Name of the ProGet Chocolatey packages feed (e.g., internal-choco).  

.PARAMETER ChocoPackageSourceRoot
    Root directory where Chocolatey package source folders are located (e.g., E:\Choco\Packages).

.PARAMETER WhatIfPublish
    Test Mode switch that does everything except ProGet upload and push.

.PARAMETER Force
    To force a package update, even if there is now new version available. Caution! Use this only for testing scenarios or you will poison your nuspec and asset.


.LINK
	https://github.com/microsoft/winget-pkgs  
	https://learn.microsoft.com/en-us/windows/package-manager/winget/  
	https://learn.microsoft.com/en-us/powershell/module/powershell-yaml  
	https://github.com/PScherling
    
.NOTES
          FileName: UpdateSoftwarePackages.ps1
          Solution: Auto-Update Software Packages for Chocolatey on ProGet Repository
          Author: Patrick Scherling
          Contact: @Patrick Scherling
          Primary: @Patrick Scherling
          Created: 2025-07-16
          Modified: 2026-02-26

          Version - 0.0.1 - () - Finalized functional version 1.
          Version - 0.0.2 - () - Adapting Software Directory Structure.
          Version - 0.0.3 - () - Finalized functional version.
          Version - 0.0.4 - () - Working on LOCAL Option.
          Version - 0.0.5 - () - Working on WEB Option.
          Version - 0.0.6 - () - Bug fixing.
          Version - 0.0.7 - () - Bug fixing.
          Version - 0.0.8 - () - Update parse yaml logic for "nestedInstallers"
          Version - 0.0.9 - () - Cleanup of obsolete code
		  Version - 0.0.10 - (2026-01-23) - Adapting for ProGet and Chocolatey Envoronment
          Version - 0.0.11 - (2026-01-26) - Reconstructuring Script...
		  Version - 0.0.12 - (2026-02-03) - Quality of Life improvement
		  Version - 0.0.13 - (2026-02-17) - Bugfix by constructing the final file name. Conversion for ProGet did not include subnames after a matched installer was found.
		  Version - 0.0.14 - (2026-02-17) - Bugfix by by handling of zip files and nested installers
          Version - 0.0.15 - (2026-02-18) - Major Bug-Fixing
          Version - 0.0.16 - (2026-02-18) - Adding security mechanics regarding api-tokens
          Version - 0.1.0 - (2026-02-18) - Release of Major Version 1
          Version - 0.1.1 - (2026-02-23) - Major Update
                                            Beginning of refactoring the whole script structure
                                            - Model: Discover latest -> Resolve installer candidate -> Download -> (optional) Extract nested -> Upload to ProGet Assets 
                                                        -> Update package source (nuspec/install script/checksums) -> Pack & push -> Cleanup
                                            - Introducing 'SpurceType' for the 'SoftwareList.csv' list (Right now UpdateOption mixes source type and execution mode.)
                                                Now I split this into two concepts: 
                                                 -> 'RunMode': ALL | API | WEB | LOCAL (what I already have)
                                                 -> 'SourceType': Winget | GitHubRelease | WebDirectory | DirectUrl | Local
                                                 -> 'SourceRef': This is provider specific.
                                                        - Winget: PackageIdentifier (e.g. Microsoft.VCLibs.Desktop.14)
                                                        - GitHubRelease: owner/repo (e.g. chocolatey/ChocolateyGUI)
                                                        - WebDirectory: a directory URL ending with / (e.g. https://packages.vmware.com/tools/esx/latest/windows/x64/)
                                                        - DirectUrl: a direct or redirecting URL that yields a file (e.g. Chocolatey v2 endpoint)
                                                        - Local: empty (because the file is already in your local download folder)
                                                 -> 'AssetPattern (optional): Used mainly for GitHubRelease to select the correct asset from the release
                                                        - E.g.: .*x64.*\.msi$
                                                                ChocolateyGUI.*\.msi$
                                                                .*\.exe$
                                                 -> 'ManualVersionRequired' (optional)
                                                        - true: always prompt for version (your chosen LOCAL behavior)
                                                        - false/empty: allow auto-detection if you ever want it

                                                This lets me keep the current UX ("run API only / WEB only / LOCAL only") while still adding clean source providers.

                                                 Example:
                                                 Publisher  | SoftwareName  | SubName1 | SubName2 | PreferredExtension | Arch | UpdateOption | SourceType    | SourceRef                                                  | AssetPattern  | ManualVersionRequired | Notes
                                                 7zip       | 7zip          |          |          | .msi               | x64  | API          | Winget        | 7zip.7zip                                                  |               | false                 |
                                                 Chocolatey | ChocolateyGUI |          |          | .msi               | x64  | API          | GitHubRelease | chocolatey/ChocolateyGUI                                   | .*x64.*\.msi$ | false                 |
                                                 VMware     | VMwareTools   |          |          | .exe               | x64  | WEB          | WebDirectory  | https://packages.vmware.com/tools/esx/latest/windows/x64/  | .*\.exe$      | false                 |
                                                 Chocolatey | Chocolatey    |          |          | .nupkg             | x64  | WEB          | DirectUrl     | https://community.chocolatey.org/api/v2/package/chocolatey |               | false                 |
                                                 AMD        | Adrenalin     |          |          | .exe               | x64  | LOCAL        | Local         |                                                            |               | false                 | 
                                                 nVidia     | QuadroRTX     |          |          | .exe               | x64  | LOCAL        | Local         |                                                            |               | true                  | 
          
          Version - 0.1.2 - (2026-02-25) - Special Handling for MS Office Packages since 2019 and onward, they need CDN/ODT approaches
                                            - Adding new SourceType 'OfficeCDN'
                                            - CSV Entry Example:
                                                Publisher  | SoftwareName   | SubName1 | SubName2 | PreferredExtension | Arch | UpdateOption | SourceType    | SourceRef                                                  | AssetPattern  | ManualVersionRequired | Notes
                                                Microsoft  | OfficeLTSC2024 | ProPlus  |          | .exe               | x64  | LOCAL        | OfficeCdn     | Microsoft.Office.LTSC.2021.ProPlus                         |               | true                  |
                                                Microsoft  | OfficeLTSC2024 | Standard |          | .exe               | x64  | LOCAL        | OfficeCdn     | Microsoft.Office.LTSC.2021.Standard                        |               | true                  |
                                            - New Function "Resolve-IntentFromOfficeCdn"

          Version - 0.1.3 - (2026-02-26) - New Functions to compare available version with current version. Approach is to use a "version.json" like we do with the checksums (Maybe a good idea to generalize this approach for all software packages in the future)
                                            - Get-OfficeVersion -> Get current office version from "version.json" if present from the local package directory
                                            - Set-OfficeVersion -> Sets new Office Version in 'version.json'

          Version - 0.1.4 - (2026-03-02) - Struggling with "Publish-ProGetAssetFile"; 
                                            Invoce-WebRequest etc. not the best option. Fails with Files larger than 2GB. Maybe .Net HTTP Client HAndler the better option?

          TODO:

.Requirements
	- PowerShell 5.1 or higher (PowerShell 7+ recommended)
	- GitHub Personal Access Token for API access
	- Module: `powershell-yaml` (auto-installed if missing)
	- Internet access for API and web modes
	- Access to ProGet Assets and Feeds
		
.Example
	PS> .\UpdateSoftwarePackages.ps1
	Starts the script

	PS> .\UpdateSoftwarePackages.ps1 `
	-UpdateOption WEB `
	-ProGetFeedApiKey 1234abcd `
	-ProGetAssetApiKey 1234abcd `
	-ProGetBaseUrl https://psc-swrepo1.local:8625 `
	-ProGetAssetDir choco-assets `
	-ProGetChocoFeedName choco-production `
	-ChocoPackageSourceRoot E:\Choco\Packages

	PS> .\UpdateSoftwarePackages.ps1 `
	-UpdateOption LOCAL `
	-ProGetFeedApiKey 1234abcd `
	-ProGetAssetApiKey 1234abcd `
	-ProGetBaseUrl https://psc-swrepo1.local:8625 `
	-ProGetAssetDir choco-assets `
	-ProGetChocoFeedName choco-production `
	-ChocoPackageSourceRoot E:\Choco\Packages

	PS> .\UpdateSoftwarePackages.ps1 `
	-UpdateOption API `
	-GitToken github_abc_defg1234 `
	-ProGetFeedApiKey 1234abcd `
	-ProGetAssetApiKey 1234abcd `
	-ProGetBaseUrl https://psc-swrepo1.local:8625 `
	-ProGetAssetDir choco-assets `
	-ProGetChocoFeedName choco-production `
	-ChocoPackageSourceRoot E:\Choco\Packages
#>

param(
    [Parameter(Mandatory = $false)] [ValidateSet('ALL','API','WEB','LOCAL')] [string] $UpdateOption = "ALL",                        # e.g. ALL, API, WEB, LOCAL | Default = ALL
    [Parameter(Mandatory = $false)] [string] $GitToken,                                                                             # GitHub Personal Access Token  
    [Parameter(Mandatory = $false)] [string] $ProGetFeedApiKey,                                                                     # ProGet Feed API Key (Feed of choco-packages)
    [Parameter(Mandatory = $false)] [string] $ProGetAssetApiKey,                                                                    # ProGet Asset API Key (Asset Repository of installer files)                                         
    [Parameter(Mandatory)] [string] $ProGetBaseUrl,                                                                                 # e.g. http://PSC-SWREPO1:8624     
    [Parameter(Mandatory)] [string] $ProGetAssetDir,                                                                                # e.g. choco-assets   
    [Parameter(Mandatory)] [string] $ProGetChocoFeedName,                                                                           # e.g. internal-choco   
    [Parameter(Mandatory)] [string] $ChocoPackageSourceRoot,                                                                        # e.g. E:\Choco\Packages     
    [Parameter(Mandatory = $false)] [switch] $WhatIfPublish,                                                                        # Switch to run everything except ProGet upload and push (good for testing)
    [Parameter(Mandatory = $false)] [switch] $Force                                                                                 # Switch to force Update process, even if current verison is the latest available version        
)

if (Get-Module -ListAvailable -Name PSReadLine) {
    Set-PSReadLineOption -HistorySaveStyle SaveNothing
}

Clear-Host






###
### Config
###
$global:WarningCount 			= 0
$global:ErrorCount 				= 0
$filetimestamp 					= Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$BaseDir						= "E:\ChocoManage"
$logDir							= "$($BaseDir)\Logs\UpdateSoftwarePackages"
$logPath 						= Join-Path -Path "$($logDir)" -ChildPath "UpdateSoftwarePackages_$($filetimestamp).log"
$userInput 					    = ""
$baseApiUrl 					= "https://api.github.com/repos/microsoft/winget-pkgs/contents/manifests"
$baseRawUrl 					= "https://raw.githubusercontent.com/microsoft/winget-pkgs/master/manifests"
$selectedUpdateOption 			= "ALL" # Defualt is ALL | Options: ALL, API, WEB or LOCAL
$csvPath 						= Join-Path -Path "$($BaseDir)" -ChildPath "SofwareList.csv"
$downloadPath 					= "$($BaseDir)\temp\Downloads"

# Mapping known InstallerType values to extensions
$installerTypeToExtension = @{
    exe     = "exe"
    msi     = "msi"
    msu     = "msu"
    msix    = "msix"
    appx    = "appx"
    appxbundle  = "appxbundle"
    msixbundle  = "msixbundle"
    nullsoft = "exe"
    inno    = "exe"
    wix     = "msi"
    burn    = "exe"
    zip     = "zip"
}

# Mapping known Architecture values
$installerArchType = @{
    x86     = "x86"
    x64     = "x64"
}


# ProGet Environment
$ProGetChocoPushUrl   			= "$($ProGetBaseUrl)/nuget/$($ProGetChocoFeedName)"  # works with choco push
$newAssetFileSHA256             = ""





###
### Creating needed directories
###
if (-not (Test-Path $logDir)) {
    Write-Host "Log Directory not found. Creating '$($logDir)'"
    try{
        New-Item -ItemType Directory -Path $logDir | Out-Null
    } catch{
        #Write-Error "Download directory could not be created. $_"
        throw "ERROR: Log directory could not be created. $_"
    }
}

if (-not (Test-Path $logPath)) {
    #Write-Host "Creating '$($logPath)'"
    try{
        New-Item -ItemType File -Path $logPath | Out-Null
    } catch{
        #Write-Error "Download directory could not be created. $_"
        throw "ERROR: Log file could not be created. $_"
    }
}

if (-not (Test-Path $downloadPath)) {
    Write-Host "Download Directory not found. Creating '$($downloadPath)'"
    try{
        New-Item -ItemType Directory -Path $downloadPath | Out-Null
    } catch{
        throw "ERROR: Download directory could not be created. $_"
    }
}






###
### Logging
###
function Write-Log {
    param([string]$msg)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $msg" | Out-File -FilePath $logPath -Append
    #Write-Host $msg
}

# Tracking Warnings
function Write-TrackedWarning {
    param([string]$Message)
    $global:WarningCount++
    Write-Host -ForegroundColor Yellow $Message
}

# Tracking Errors
function Write-TrackedError {
    param([string]$Message)
    $global:ErrorCount++
    Write-Host -ForegroundColor Red $Message
}




###
### Base Functions
###

# CSV import normalization
function New-SoftwareSpec {
    param([pscustomobject]$row)

    [pscustomobject]@{
        Publisher             = $row.Publisher
        SoftwareName          = $row.SoftwareName
        SubName1              = $row.SubName1
        SubName2              = $row.SubName2
        PreferredExtension    = $row.PreferredExtension
        Arch                  = $row.Arch
        UpdateOption          = $row.UpdateOption
        SourceType            = $row.SourceType
        SourceRef             = $row.SourceRef
        ManifestSubPath       = $row.ManifestSubPath
        AssetPattern          = $row.AssetPattern
        ManualVersionRequired = if ($row.ManualVersionRequired) { [bool]::Parse($row.ManualVersionRequired) } else { $false }
    }
}

# Provider switch
function Resolve-LatestReleaseIntent {
    param(
        [Parameter(Mandatory)] $Software,
        [Parameter(Mandatory)] $Paths,
        [Parameter(Mandatory)] [string] $DownloadPath
    )

    $intent = $null

    $intent = switch ($Software.SourceType) {
        'Winget'        { return Resolve-IntentFromWinget -Software $Software -Paths $Paths }
        'GitHubRelease' { return Resolve-IntentFromGitHubRelease -Software $Software -Paths $Paths }
        'WebDirectory'  { return Resolve-IntentFromWebDirectory -Software $Software -Paths $Paths }
        'DirectUrl'     { return Resolve-IntentFromDirectUrl -Software $Software -Paths $Paths }
        'Local'         { return Resolve-IntentFromLocal -Software $Software -Paths $Paths -DownloadPath $DownloadPath }
        'OfficeCdn'     { return Resolve-IntentFromOfficeCdn -Software $Software -Paths $Paths -DownloadPath $DownloadPath }
        default         { throw "Unknown SourceType '$($Software.SourceType)' for $($Software.Publisher)/$($Software.SoftwareName)" }
    }

    # -------------------------
    # Normalize Intent
    # -------------------------
    if ($null -ne $intent) {

        # Version
        if ([string]::IsNullOrWhiteSpace($intent.Version)) {
            if (-not [string]::IsNullOrWhiteSpace($intent.LatestVersion)) { $intent.Version = $intent.LatestVersion }
            elseif (-not [string]::IsNullOrWhiteSpace($intent.ReleaseVersion)) { $intent.Version = $intent.ReleaseVersion }
        }

        # URL
        if ([string]::IsNullOrWhiteSpace($intent.InstallerUrl) -and -not [string]::IsNullOrWhiteSpace($intent.Url)) {
            $intent.InstallerUrl = $intent.Url
        }

        # Extension fallback
        if ([string]::IsNullOrWhiteSpace($intent.Extension) -and -not [string]::IsNullOrWhiteSpace($Software.PreferredExtension)) {
            $intent.Extension = $Software.PreferredExtension
        }

        # Optional: ensure SourceType is set
        if ([string]::IsNullOrWhiteSpace($intent.SourceType)) {
            $intent | Add-Member -NotePropertyName SourceType -NotePropertyValue $Software.SourceType -Force
        }
    }

    return $intent
}

# LOCAL Provider
function Resolve-IntentFromLocal {
    param(
        [Parameter(Mandatory)] $Software,
        [Parameter(Mandatory)] $Paths,
        [Parameter(Mandatory)] [string] $DownloadPath
    )

    $ext = $Software.PreferredExtension
    $softwareNameLower = $Software.SoftwareName.ToLower()
    $publisherLower    = $Software.Publisher.ToLower()
    $Ref               = $Software.SourceRef

    $picked = $null
    Write-Log "===== Listing available candidates ====="
    $candidates = Get-ChildItem -Path $DownloadPath -Filter "*$ext" -ErrorAction SilentlyContinue | 
        ForEach-Object {
            $score = 0
            $v = $_.VersionInfo
            
            # DEBUG
            #Write-Host -ForegroundColor Cyan "$v"
            # DEBUG

            if ($_.BaseName.ToLower().Contains($softwareNameLower)) { 
                $score += 3 
            }
            if ($_.BaseName.ToLower().Contains($publisherLower)) { 
                $score += 1
            }

            if ($v) {
                $prod = if ($v.ProductName) { $v.ProductName.ToLower() } else { '' }
                $desc = if ($v.FileDescription) { $v.FileDescription.ToLower() } else { '' }

                if ($prod.Contains($softwareNameLower)) { 
                    $score += 5 
                }

                if ($prod.Contains($publisherLower) -or $desc.Contains($publisherLower)) { 
                    $score += 1 
                }

                if($_.BaseName -like "*$($Ref)*") {
                    $score += 6
                }

                if($prod -eq $Ref) {
                    $score += 15
                }
            }

            Write-Log "Candidate: $($_.BaseName) | Score: $score"

            [pscustomobject]@{ File = $_; Score = $score }
    }

    <#
    $picked = $candidates | 
        Where-Object { 
            $_.File.Name -like "*$($Software.Publisher)*" -or $_.File.Name -like "*$($Software.SoftwareName)*" -or $_.File.Name -like "*$($Ref)*" 
        } | 
        Sort-Object Score -Descending | 
        Select-Object -First 1 | 
        Select-Object File, Score #Select-Object -ExpandProperty File
    #>
    
    $rankedCandidates = $candidates | Where-Object { $_.Score -ge 3 }

    $picked = $rankedCandidates | 
        Sort-Object Score -Descending | 
        Select-Object -First 1 | 
        Select-Object File, Score #Select-Object -ExpandProperty File
    

    if (-not $picked) {
        Write-TrackedError "No matching file found in '$DownloadPath' for $($Software.Publisher) $($Software.SoftwareName) ($($Software.Arch)$ext)"
        Write-Log "ERROR: No matching file found in '$DownloadPath' for $($Software.Publisher) $($Software.SoftwareName) ($($Software.Arch)$ext)"
        return $null
    }
    else{
        Write-Log "Picked candidate: $($picked.File.Name) | Score: $($picked.Score)"
        Write-Host -ForegroundColor Magenta "    Picked candidate: $($picked.File.Name) | Score: $($picked.Score)"
    }
    Write-Log "========================================"

    # Force version prompt (as you want)
    if($Software.ManualVersionRequired){
        $inputVersion = Read-Host "LOCAL: Provide new version for '$($Software.Publisher) $($Software.SoftwareName) ($($Software.Arch))' | (e.g. 1.2.4)"
        if ($inputVersion -notmatch '^\d+(\.\d+){1,3}$') {
            Write-TrackedError "LOCAL: Invalid version format '$inputVersion' (expected X.Y[.Z[.W]])"
            return $null
        }
        $ver = ([version]$inputVersion).ToString()
    }
    else{
        $ver = ([version]$picked.File.VersionInfo.ProductVersion).ToString()
    }
    Write-Host -ForegroundColor Magenta "    Provided Version: $ver"
    Write-Log "Provided Version: $ver"

    return [pscustomobject]@{
        SourceType      = 'Local'
        Version         = $ver
        InstallerUrl    = $null
        FileName        = $picked.File.Name
        Extension       = $Software.PreferredExtension
        Sha256          = $null
        Nested          = $null
        LocalPickedFile = $picked.File.FullName
    }
}

# MS OfficeCdn Provider
function Resolve-IntentFromOfficeCdn {
    param(
        [Parameter(Mandatory)] $Software,
        [Parameter(Mandatory)] $Paths,
        [Parameter(Mandatory)] [string] $DownloadPath
    )

    $officeKey = "$($Software.SoftwareName)$($Software.SubName1)"

    $scriptPath = Join-Path "$($BaseDir)" "UpdateMSOffice.ps1"
    if (-not (Test-Path $scriptPath)) {
        Write-TrackedError "OfficeCdn: Script for updating MS Office Packages not found."
        Write-Log "ERROR: Script 'UpdateMSOffice.ps1' not found - $_"
        return $null
    }
    else{
        Write-Log "OfficeCdn: Calling '$($scriptPath)' for key '$($officeKey)'"
        Write-Host "    OfficeCdn: Calling '$($scriptPath)' for key '$($officeKey)'"

        # Forward WhatIf if your main script supports it
        if ($WhatIfPublish) {
            Write-Log "WHATIFPUBLISH Enabled -> Execution of script 'UpdateMSOffice.ps1' -OfficeKey $($officeKey) -BaseDir $($BaseDir) -RunNotStandalone -ReturnObject -WhatIf"
            Write-Host -ForegroundColor Yellow "    WHATIFPUBLISH Enabled -> Execution of script 'UpdateMSOffice.ps1' -OfficeKey $($officeKey) -BaseDir $($BaseDir) -RunNotStandalone -ReturnObject -WhatIf"
            $result = & $scriptPath -OfficeKey $officeKey -BaseDir $BaseDir -RunNotStandalone -ReturnObject -WhatIf
        }
        else{
            Write-Log "Execution of script 'UpdateMSOffice.ps1' -OfficeKey $($officeKey) -BaseDir $($BaseDir) -RunNotStandalone -ReturnObject"
            Write-Host -ForegroundColor Magenta "    Execution of script 'UpdateMSOffice.ps1' -OfficeKey $($officeKey) -BaseDir $($BaseDir) -RunNotStandalone -ReturnObject"
            $result = & $scriptPath -OfficeKey $officeKey -BaseDir $BaseDir -RunNotStandalone -ReturnObject -WhatIf
        }

        <# DEBUG 
        if ($result) {
            Write-Host "DEBUG result type: $($result.GetType().FullName)" -ForegroundColor Magenta
            $result | Format-List * | Out-String | Write-Host
        }
        DEBUG #>
        
        if (-not $result ) {
            Write-TrackedError "OfficeCdn: Failed return object for $officeKey"
            Write-Log "ERROR: Failed return object for $officeKey"
            return $null
        }
        elseif (-not $result.Success) {
            Write-TrackedError "OfficeCdn: Failed to refresh Office source for $officeKey"
            Write-Log "ERROR: Failed to refresh Office source for $officeKey"
            return $null
        }
        elseif (-not $result.WhatIf -and -not (Test-Path $result.PackageFile)) {
            Write-TrackedError "OfficeCdn: Package file not found: '$($result.PackageFile)'"
            Write-Log "ERROR: Package file not found: '$($result.PackageFile)'"
            return $null
        }

        # If UpdateMSOffice didn't create a zip, create it here from the known folder layout
        <#
        Need to create a function"New-OfficePackageZip" like in "UpdateMSOffice.ps1"
        if (-not $result.PackageFile) {
            Write-Log "OfficeCDN: Creating package file '$($result.PackageFile)'"
            Write-Host -ForegroundColor Magenta "    OfficeCDN: Creating package file '$($result.PackageFile)'"

            $edition = $Software.SubName1  # ProPlus / Standard
            $officeName = $Software.SoftwareName # OfficeLTSC2021, OfficeLTSC2024
            $version = $result.Version
            $zipName = "{0}_{1}_x64_{2}.zip" -f $officeName, $edition, $version
            $zipPath = Join-Path $DownloadPath $zipName

            $zipPath = New-OfficePackageZip -ItemPath $result.SourceFolder -OfficeName $officeName -Edition $edition -Version $version -DownloadPath $DownloadPath
            $result | Add-Member -NotePropertyName PackageFile -NotePropertyValue $zipPath -Force
            $result | Add-Member -NotePropertyName PackageFileName -NotePropertyValue ([IO.Path]::GetFileName($zipPath)) -Force
        }
        #>

        return [pscustomobject]@{
            SourceType      = 'OfficeCDN'
            Version         = $result.Version
            InstallerUrl    = $null
            FileName        = $result.PackageFileName
            Extension       = '.zip'
            Sha256          = $null
            Nested          = $null
            LocalPickedFile = $result.PackageFile
        }
    }
    
}

# DirectUrl Provider
function Resolve-IntentFromDirectUrl {
    param(
        [Parameter(Mandatory)] $Software,
        [Parameter(Mandatory)] $Paths
    )

    $info = Resolve-DownloadInfo -Url $Software.SourceRef -SoftwareName $Software.SoftwareName -PreferredExtension $Software.PreferredExtension
    if (-not $info) {
        Write-TrackedError "DirectUrl: Could not resolve download info from $($Software.SourceRef)"
        return $null
    }

    # version may be unknown - you can either parse from filename OR prompt in LOCAL only.
    # For DirectUrl, try parse from filename; if absent you can keep 'UNKNOWN' and skip compare OR require version in CSV later.
    $ver = $null
    if ($info.FileName -match '(\d+(\.\d+){1,3})') { 
        $ver = ([version]$matches[1])
    }
    if (-not $ver) { 
        $ver = "0.0.0.0" # signals "no compare"; we'll handle later
    } 

    return [pscustomobject]@{
        SourceType      = 'DirectUrl'
        Version         = $ver
        InstallerUrl    = $info.DownloadUrl
        FileName        = $info.FileName
        Extension       = [IO.Path]::GetExtension($info.FileName)
        Sha256          = $null
        Nested          = $null
        LocalPickedFile = $null
    }
}

# WebDirectory Provider
function Resolve-IntentFromWebDirectory {
    param(
        [Parameter(Mandatory)] $Software,
        [Parameter(Mandatory)] $Paths
    )

    $info = Resolve-DownloadInfo -Url $Software.SourceRef -SoftwareName $Software.SoftwareName -PreferredExtension $Software.PreferredExtension
    if (-not $info) {
        Write-TrackedError "WebDirectory: Could not resolve from $($Software.SourceRef)"
        return $null
    }

    $ver = $null
    if ($info.FileName -match '(\d+(\.\d+){1,3})') { 
        $ver = ([version]$matches[1]) 
    }
    if (-not $ver) { 
        $ver = "0.0.0.0" 
    }

    return [pscustomobject]@{
        SourceType      = 'WebDirectory'
        Version         = $ver
        InstallerUrl    = $info.DownloadUrl
        FileName        = $info.FileName
        Extension       = [IO.Path]::GetExtension($info.FileName)
        Sha256          = $null
        Nested          = $null
        LocalPickedFile = $null
    }
}

# GitHubRelease Provider
function Resolve-IntentFromGitHubRelease {
    param(
        [Parameter(Mandatory)] $Software,
        [Parameter(Mandatory)] $Paths
    )

    $repo = $Software.SourceRef # owner/repo
    $apiUrl = "https://api.github.com/repos/$($repo)/releases/latest"

    $headers = @{ "User-Agent" = "PowerShell" }
    if ($script:GitToken) { $headers.Authorization = "token $script:GitToken" }

    $rel = Invoke-RestMethod -Uri $apiUrl -Headers $headers -ErrorAction Stop

    $version = $rel.tag_name
    if ($version -match '(\d+(\.\d+){1,3})') { 
        $version = ([version]$matches[1])
    }
    else { 
        $version = "0.0.0.0" 
    }

    $pattern = if ($Software.AssetPattern) { $Software.AssetPattern } else { ".*\Q$($Software.PreferredExtension)\E$" }
    $asset = $rel.assets | Where-Object { $_.name -match $pattern } | Select-Object -First 1
    if (-not $asset) {
        $assetNames = @($rel.assets | ForEach-Object { $_.name }) -join ', '
        Write-TrackedError "GitHubRelease: No asset matched pattern '$pattern' for $repo"
        Write-TrackedWarning "GitHubRelease: Available assets: $assetNames"
        Write-Log "GitHubRelease assets for $($repo): $assetNames"
        return $null

        #$extPattern = [regex]::Escape($Software.PreferredExtension) + '$'
        #$asset = $rel.assets | Where-Object { $_.name -match $extPattern } | Select-Object -First 1
    }

    return [pscustomobject]@{
        SourceType      = 'GitHubRelease'
        Version         = $version
        InstallerUrl    = $asset.browser_download_url
        FileName        = $asset.name
        Extension       = [IO.Path]::GetExtension($asset.name)
        Sha256          = $null
        Nested          = $null
        LocalPickedFile = $null
    }
}

# Winget Provider
function Resolve-IntentFromWinget {
    param(
        [Parameter(Mandatory)] $Software,
        [Parameter(Mandatory)] $Paths
    )

    $apiUrl = $paths.ApiUrl
    $rawUrl = $paths.RawUrl
    
    $headers = @{ "User-Agent" = "PowerShell" }
    if ($script:GitToken) { 
        $headers.Authorization = "token $script:GitToken" 
    }

    # 1) list version folders
    $versionsJson = Invoke-RestMethod -Uri $apiUrl -Headers $headers -ErrorAction Stop
    $versionDirs = $versionsJson | Where-Object { $_.type -eq "dir" } | Select-Object -ExpandProperty name

    # 2) parse semantic versions
    $parsed = foreach ($dir in $versionDirs) {
        if ($dir -match '^\d+(\.\d+){1,3}$') {
            [pscustomobject]@{ 
                Original = $dir 
                Parsed = [version]$dir 
            }
        }
    }
    if (-not $parsed) {
        Write-TrackedWarning "Winget: No valid semantic versions found for $($Software.Publisher)/$($Software.SoftwareName)"
        return $null
    }

    $latest = $parsed | Sort-Object Parsed -Descending | Select-Object -First 1
    $latestVersion = $latest.Original

    # 3) list files inside latest version folder
    $versionApiUrl = "$apiUrl/$latestVersion"
    $filesJson = Invoke-RestMethod -Uri $versionApiUrl -Headers $headers -ErrorAction Stop

    $yamlFile = $filesJson | Where-Object { $_.name -like "*.installer.yaml" } | Select-Object -First 1 -ExpandProperty name
    if (-not $yamlFile) {
        Write-TrackedWarning "Winget: No *.installer.yaml found for $($Software.SoftwareName) version $latestVersion"
        return $null
    }

    # 4) download raw yaml
    $rawYamlUrl = "$rawUrl/$latestVersion/$yamlFile"
    $yamlContent = Invoke-RestMethod -Uri $rawYamlUrl -Headers $headers -ErrorAction Stop
    $yamlParsed = $yamlContent | ConvertFrom-Yaml

    $preferredExt = $Software.PreferredExtension.TrimStart('.').ToLower()

    # 5) inherit top-level InstallerType if missing
    $installers = $yamlParsed.Installers | ForEach-Object {
        if (-not $_.InstallerType -and $yamlParsed.InstallerType) {
            $_ | Add-Member -MemberType NoteProperty -Name InstallerType -Value $yamlParsed.InstallerType -Force
        }
        $_
    }

    # 6) try direct match first
    $installer = $installers | Where-Object {
        $_.Architecture -eq $Software.Arch -and (
            ($installerTypeToExtension[$_.InstallerType] -eq $preferredExt) -or
            ($_.InstallerUrl -like "*.$preferredExt*")
        )
    } | Select-Object -First 1

    $nested = $null

    # 7) fallback: nested installer type
    if (-not $installer) {
        $nestedInstallers = $yamlParsed.Installers | ForEach-Object {
            if (-not $_.NestedInstallerType -and $yamlParsed.NestedInstallerType) {
                $_ | Add-Member -MemberType NoteProperty -Name NestedInstallerType -Value $yamlParsed.NestedInstallerType -Force
            }
            $_
        }

        $nestedInstaller = $nestedInstallers | Where-Object {
            $_.Architecture -eq $Software.Arch -and
            ($installerTypeToExtension[$_.NestedInstallerType] -eq $preferredExt)
        } | Select-Object -First 1

        if (-not $nestedInstaller) {
            Write-TrackedWarning "Winget: No installer match for $($Software.SoftwareName) Arch $($Software.Arch) ext .$preferredExt (direct or nested)"
            return $null
        }

        # pick nested relative file path (usually only one per arch)
        $relativePath = $null
        if ($nestedInstaller.NestedInstallerFiles) {
            $match = $nestedInstaller.NestedInstallerFiles | Select-Object -First 1
            if ($match -and $match.RelativeFilePath) { $relativePath = $match.RelativeFilePath }
        }

        if (-not $relativePath) {
            Write-TrackedWarning "Winget: Nested installer selected but no NestedInstallerFiles.RelativeFilePath found for $($Software.SoftwareName)"
            return $null
        }

        $installer = $nestedInstaller
        $nested = @{
            RelativeFilePath = $relativePath
        }
    }

    # 8) build filename/extension
    $installerUrl = $installer.InstallerUrl
    $ext = [IO.Path]::GetExtension(($installerUrl -split '\?')[0])
    if (-not $ext) {
        # fall back to preferred extension if URL has no extension (rare)
        $ext = $Software.PreferredExtension
    }

    # If nested: the outer file is zip, inner is preferred extension
    if ($nested) {
        $ext = ".zip"
    }

    # Make a deterministic download name (we'll still rename later to your naming convention)
    $fileName = [IO.Path]::GetFileName(($installerUrl -split '\?')[0])
    if (-not $fileName) {
        # fallback if URL doesn't end with a name
        $fileName = "$($Software.SoftwareName)_$($Software.Arch)_$latestVersion$ext"
    }

    <# DEBUG #>
    #Write-Host -ForegroundColor Cyan "Winget intent debug (inside): Version='$latestVersion' Url='$installerUrl'"
    #Write-Log  "Winget intent debug (inside): Version='$latestVersion' Url='$installerUrl'"
    <# DEBUG #>

    return [pscustomobject]@{
        SourceType      = 'Winget'
        Version         = $latestVersion
        InstallerUrl    = $installerUrl
        FileName        = $fileName
        Extension       = $ext
        Sha256          = $installer.InstallerSha256
        Nested          = $nested
        LocalPickedFile = $null
    }
}

# Define Software Paths
function Get-SoftwarePaths {
    param (
        [string]$Publisher,
        [string]$SoftwareName,
        [string]$SubName1,
        [string]$SubName2,
        [string]$ManifestSubPath,
        [string]$Option
    )
	
	Write-Log "--------------------------------"
	Write-Log "Attempt to get software paths:"
	Write-Log "Publisher:             $Publisher"
	Write-Log "Software Base Name:    $SoftwareName"
	Write-Log "Sub Name 1:            $SubName1"
	Write-Log "Sub Name 2:            $SubName2"
    Write-Log "Manifest Sub Path:     $ManifestSubPath"
    Write-Log "Update Option:         $Option"
	

    $firstLetter = $Publisher.Substring(0,1).ToLower()
	$publisherForLocal = Convert-NameForProGetPath $Publisher
	$softwareForLocal = Convert-NameForProGetPath $SoftwareName
    $publisherForAssets = Convert-NameForProGetPath $Publisher
    $softwareForAssets  = Convert-NameForProGetPath $SoftwareName
	


    if ([string]::IsNullOrEmpty($SubName1) -and [string]::IsNullOrEmpty($SubName2) -and [string]::IsNullOrEmpty($ManifestSubPath)) {
        Write-Log "Sub Names are null or empty."
		$subFolder1 = ""
        $subFolder2 = ""
        $ManifestSubPath = ""
		
		if($Option -ne "LOCAL"){
            $paths = @{
                FirstLetter        = $firstLetter
                ApiUrl             = "$($baseApiUrl)/$($firstLetter)/$($Publisher)/$($SoftwareName)"
                RawUrl             = "$($baseRawUrl)/$($firstLetter)/$($Publisher)/$($SoftwareName)"
                #LocalStoragePath   = "$($ChocoPackageSourceRoot)\$($Publisher)\$($SoftwareName)"
                LocalStoragePath	= "$($ChocoPackageSourceRoot)\$($publisherForLocal)\$($softwareForLocal)"
                ProGetAssetRelativePath = "$($publisherForAssets)/$($softwareForAssets)" 
            }
        }
        else{
            $paths = @{
                FirstLetter        = $firstLetter
                ApiUrl             = "-"
                RawUrl             = "-"
                #LocalStoragePath   = "$($ChocoPackageSourceRoot)\$($Publisher)\$($SoftwareName)"
                LocalStoragePath	= "$($ChocoPackageSourceRoot)\$($publisherForLocal)\$($softwareForLocal)"
                ProGetAssetRelativePath = "$($publisherForAssets)/$($softwareForAssets)" 
            }
        }
    } 
    elseif(-not [string]::IsNullOrEmpty($SubName1) -and [string]::IsNullOrEmpty($SubName2) -and [string]::IsNullOrEmpty($ManifestSubPath)){
        Write-Log "Sub Name1 not null or empty."
		$subFolder1 = "$($SubName1)"
		$convertedSubFolder1 = Convert-NameForProGetPath "$($SubName1)"
        $subFolder2 = ""
        $ManifestSubPath = ""
		
		Write-Log "Converted Sub Name 1: $convertedSubFolder1"


		if($Option -ne "LOCAL"){
            $paths = @{
                FirstLetter        = $firstLetter
                ApiUrl             = "$($baseApiUrl)/$($firstLetter)/$($Publisher)/$($SoftwareName)/$($subFolder1)"
                RawUrl             = "$($baseRawUrl)/$($firstLetter)/$($Publisher)/$($SoftwareName)/$($subFolder1)"
                #LocalStoragePath   = "$($ChocoPackageSourceRoot)\$($Publisher)\$($SoftwareName)\$($subFolder1)"
                LocalStoragePath	= "$($ChocoPackageSourceRoot)\$($publisherForLocal)\$($softwareForLocal)$($convertedSubFolder1)"
                ProGetAssetRelativePath = "$($publisherForAssets)/$($softwareForAssets)$($convertedSubFolder1)" 
            }
        }
        else{
            $paths = @{
                FirstLetter        = $firstLetter
                ApiUrl             = "-"
                RawUrl             = "-"
                #LocalStoragePath   = "$($ChocoPackageSourceRoot)\$($Publisher)\$($SoftwareName)\$($subFolder1)"
                LocalStoragePath	= "$($ChocoPackageSourceRoot)\$($publisherForLocal)\$($softwareForLocal)$($convertedSubFolder1)"
                ProGetAssetRelativePath = "$($publisherForAssets)/$($softwareForAssets)$($convertedSubFolder1)" 
            }
        }
    }
    elseif(-not [string]::IsNullOrEmpty($SubName1) -and -not [string]::IsNullOrEmpty($SubName2) -and [string]::IsNullOrEmpty($ManifestSubPath)){
        Write-Log "Sub Name1 and Sub Name2 not null or empty."
		$subFolder1 = "$($SubName1)"
        $subFolder2 = "$($SubName2)"
        $ManifestSubPath = ""

		$convertedSubFolder1 = Convert-NameForProGetPath "$($SubName1)"
		$convertedSubFolder2 = Convert-NameForProGetPath "$($SubName2)"
		
		Write-Log "Converted Sub Name 1: $convertedSubFolder1"
		Write-Log "Converted Sub Name 2: $convertedSubFolder2"

        if($Option -ne "LOCAL"){
            $paths = @{
                FirstLetter        = $firstLetter
                ApiUrl             = "$($baseApiUrl)/$($firstLetter)/$($Publisher)/$($SoftwareName)/$($subFolder1)/$($subFolder2)"
                RawUrl             = "$($baseRawUrl)/$($firstLetter)/$($Publisher)/$($SoftwareName)/$($subFolder1)/$($subFolder2)"
                #LocalStoragePath   = "$($ChocoPackageSourceRoot)\$($Publisher)\$($SoftwareName)\$($subFolder1)\$($subFolder2)"
                LocalStoragePath	= "$($ChocoPackageSourceRoot)\$($publisherForLocal)\$($softwareForLocal)$($convertedSubFolder1)$($convertedSubFolder2)"
                ProGetAssetRelativePath = "$($publisherForAssets)/$($softwareForAssets)$($convertedSubFolder1)$($convertedSubFolder2)" 
            }
        }
        else{
            $paths = @{
                FirstLetter        = $firstLetter
                ApiUrl             = "-"
                RawUrl             = "-"
                #LocalStoragePath   = "$($ChocoPackageSourceRoot)\$($Publisher)\$($SoftwareName)\$($subFolder1)\$($subFolder2)"
                LocalStoragePath	= "$($ChocoPackageSourceRoot)\$($publisherForLocal)\$($softwareForLocal)$($convertedSubFolder1)$($convertedSubFolder2)"
                ProGetAssetRelativePath = "$($publisherForAssets)/$($softwareForAssets)$($convertedSubFolder1)$($convertedSubFolder2)" 
            }
        }
    }

    elseif(-not [string]::IsNullOrEmpty($SubName1) -and -not [string]::IsNullOrEmpty($SubName2) -and -not [string]::IsNullOrEmpty($ManifestSubPath)) {
        Write-Log "Sub Name1, Sub Name2 and manifast path not null or empty."

        $subFolder1 = "$($SubName1)"
        $subFolder2 = "$($SubName2)"
        $ManifestPath = "$($ManifestSubPath)"

		$convertedSubFolder1 = Convert-NameForProGetPath "$($SubName1)"
		$convertedSubFolder2 = Convert-NameForProGetPath "$($SubName2)"
        $convertedManifestPath = Convert-NameForProGetPath "$($ManifestSubPath)"
		
		Write-Log "Converted Sub Name 1: $convertedSubFolder1"
		Write-Log "Converted Sub Name 2: $convertedSubFolder2"
        Write-Log "Converted Manifest PAth: $convertedManifestPath"


        if($Option -ne "LOCAL"){
            $paths = @{
                FirstLetter        = $firstLetter
                ApiUrl             = "$($baseApiUrl)/$($firstLetter)/$($Publisher)/$($SoftwareName)/$($subFolder1)/$($subFolder2)/$($ManifestPath)"
                RawUrl             = "$($baseRawUrl)/$($firstLetter)/$($Publisher)/$($SoftwareName)/$($subFolder1)/$($subFolder2)/$($ManifestPath)"
                #LocalStoragePath   = "$($ChocoPackageSourceRoot)\$($Publisher)\$($SoftwareName)\$($subFolder1)\$($subFolder2)/$($ManifestPath)"
                LocalStoragePath	= "$($ChocoPackageSourceRoot)\$($publisherForLocal)\$($softwareForLocal)$($convertedSubFolder1)$($convertedSubFolder2).$($convertedManifestPath)"
                ProGetAssetRelativePath = "$($publisherForAssets)/$($softwareForAssets)$($convertedSubFolder1)$($convertedSubFolder2).$($convertedManifestPath)" 
            }
        }
        else{
            $paths = @{
                FirstLetter        = $firstLetter
                ApiUrl             = "-"
                RawUrl             = "-"
                #LocalStoragePath   = "$($ChocoPackageSourceRoot)\$($Publisher)\$($SoftwareName)\$($subFolder1)\$($subFolder2)/$($ManifestPath)"
                LocalStoragePath	= "$($ChocoPackageSourceRoot)\$($publisherForLocal)\$($softwareForLocal)$($convertedSubFolder1)$($convertedSubFolder2).$($convertedManifestPath)"
                ProGetAssetRelativePath = "$($publisherForAssets)/$($softwareForAssets)$($convertedSubFolder1)$($convertedSubFolder2).$($convertedManifestPath)" 
            }
        }

        # ensure no leading/trailing slashes
        #$m = $ManifestPath.Trim('/')
        #$paths.ApiUrl = "$($paths.ApiUrl)/$($m)"
        #$paths.RawUrl = "$($paths.RawUrl)/$($m)"
    }
	
    Write-Log "API Url:                       $($paths.ApiUrl)"
    Write-Log "API RAW Url:                   $($paths.RawUrl)"
	Write-Log "Local Storage Path:            $($paths.LocalStoragePath)"
	Write-Log "ProGet Asset Relative Path:    $($paths.ProGetAssetRelativePath)"
	Write-Log "--------------------------------"
	
    return $paths
}

# Downloading File
function Start-DownloadInstallerFile {
    param (
        [string]$Url,
        [string]$DestinationPath
    )
    $download = 1
    try {
        Start-BitsTransfer -Source $Url -Destination $DestinationPath -ErrorAction Stop
        Write-Log "Download completed using BITS: $DestinationPath"
        Write-Host "    Downloaded successfully using BITS."
    } catch {
        #Write-Warning "BITS download failed. Trying fallback method."
        Write-TrackedWarning "BITS download failed. Trying fallback method."
        Write-Log "WARNING: BITS download failed - $_"

        # Fallback: Use Invoke-WebRequest
        try {
            Write-Host "    URL: $Url"
            #Invoke-WebRequest -Uri "https://community.chocolatey.org/api/v2/package/chocolatey/" -MaximumRedirection 1 -UseBasicParsing -OutFile "E:\choco.nupkg"
            Invoke-WebRequest -Uri $Url -MaximumRedirection 1 -UseBasicParsing -OutFile $DestinationPath 
            Write-Log "Fallback download completed: $DestinationPath"
            Write-Host "    Downloaded successfully with fallback method."
        } catch {
            #Write-Warning "Fallback download failed - $_"
            Write-TrackedError "Fallback download failed - $_"
            Write-Log "ERROR: Fallback download failed - $_"
            $download = 0
            return $download
        }
    }

    return $download
}

<#
function Resolve-WebFilename {
    param (
        [string]$Url,
        [string]$SoftwareName,
        #[string]$SoftwareFileName,
        #[string]$FormattedVersion,
        [string]$PreferredExtension
    )

    $filename = Get-WebFilename -Url $Url -Extension $PreferredExtension
    Write-Log "Get-WebFilename returned: '$filename' for $SoftwareName"
    #Write-Host "    Get-WebFilename returned: '$filename' for $SoftwareName"

    return $filename
}
#>

#function Get-WebFilename {
function Resolve-DownloadInfo {
    param (
        [string]$Url,
        [string]$SoftwareName,
        [string]$PreferredExtension
    )

    try {
        $response = Invoke-WebRequest -Uri $Url -MaximumRedirection 1 -UseBasicParsing -ErrorAction Stop

        $contentType = $response.Headers["Content-Type"]
        $prefExt = $PreferredExtension.Trim().TrimStart('.')
        $extPattern = '\.' + [regex]::Escape($prefExt) + '($|\?)'

        # ----------------------------
        # CASE 1: Direct file download
        # ----------------------------
        if ($contentType -notmatch "text/html") {
            $finalUrl = $response.BaseResponse.ResponseUri.AbsoluteUri

            $cd = $response.Headers["Content-Disposition"]
            if ($cd -match 'filename="?([^";]+)"?') {
                $fileName = $matches[1]
            }
            else {
                $fileName = [System.IO.Path]::GetFileName(
                    $response.BaseResponse.ResponseUri.AbsolutePath
                )
            }

            if ([string]::IsNullOrWhiteSpace($fileName)) {
                return $null
            }

            return @{
                FileName    = $fileName
                DownloadUrl = $finalUrl
            }
        }

        # ----------------------------
        # CASE 2: HTML directory listing
        # ----------------------------
        # First try parsed links
        $fileLink = $null
        if ($response.Links) {
            $fileLink = $response.Links |
                Where-Object { $_.href -and $_.href -match $extPattern } |
                Sort-Object href -Descending |
                Select-Object -First 1
        }

        if ($fileLink) {
            $fullUrl = (New-Object System.Uri($response.BaseResponse.ResponseUri, $fileLink.href)).AbsoluteUri
            return [pscustomobject]@{
                FileName    = [System.IO.Path]::GetFileName(($fileLink.href -split '\?')[0])
                DownloadUrl = $fullUrl
            }
        }

        # Fallback: parse raw HTML manually (helps on some pages / PS versions)
        if ($response.Content) {
            $hrefMatches = [regex]::Matches($response.Content, 'href\s*=\s*"([^"]+)"', 'IgnoreCase')
            $hrefs = foreach ($m in $hrefMatches) { $m.Groups[1].Value }

            $candidate = $hrefs |
                Where-Object { $_ -match $extPattern } |
                Sort-Object -Descending |
                Select-Object -First 1

            if ($candidate) {
                $fullUrl = (New-Object System.Uri($response.BaseResponse.ResponseUri, $candidate)).AbsoluteUri
                return [pscustomobject]@{
                    FileName    = [System.IO.Path]::GetFileName(($candidate -split '\?')[0])
                    DownloadUrl = $fullUrl
                }
            }
        }

        return $null
    }
    catch {
        throw "Failed resolving filename from $Url - $($_.Exception.Message)"
        return $null
    }
}

# Remove File
function Remove-File {
    param (
        [string]$Path
    )

    Write-Log "Removing file from '$($Path)'"
    Write-Host "    Removing file from '$($Path)'"
    try {
        Remove-Item $($Path) -Force
        Write-Log "Removed file '$($Path)'"
    } catch {
        Write-Log "WARNING: Could not remove file '$($Path)' - $_"
        Write-TrackedWarning "Could not remove file '$($Path)' - $_"
    }
}

# Copy File
function Copy-File {
    param (
        [string]$Source,
        [string]$Dest
    )

    Write-Log "Copy new version to '$($Dest)'"
    Write-Host "    Copy new version to:  $($Dest)"
    try{
        Copy-Item -Path "$($Source)" -Destination "$($Dest)" -Force
        Write-Log "Copied new version to '$($Dest)'"
    } catch {
        Write-Log "ERROR: Failed to copy '$($Dest)' - $_"
        Write-TrackedError "Failed to copy '$($Dest)' - $_"
    }
}




###
### ProGet and Chocolatey Functions
###
function Publish-ProGetAssetFile {
    param(
        [Parameter(Mandatory)] [string] $LocalFilePath,     # e.g. E:\UpdateScripts\temp\Downloads\NotepadPlusPlus_x64_8.9.exe
        [Parameter(Mandatory)] [string] $AssetFolder,       # e.g. NotepadPlusPlus/NotepadPlusPlus
        [Parameter(Mandatory)] [string] $AssetFileName,     # e.g. NotepadPlusPlus_x64_8.9.exe
        [Parameter(Mandatory)] [string] $Key,
        [ValidateSet('POST','PUT','PATCH')] [string] $Method = 'POST'
    )

    <# DEBUG #>
    #Write-Host -ForegroundColor Cyan "DEBUG: Publish-ProGetAssetFile function version = STREAM"
    #Write-Log "DEBUG: Publish-ProGetAssetFile function version = STREAM"
    <# DEBUG #>

    $uri = "$($ProGetBaseUrl)/endpoints/$($ProGetAssetDir)/content/$($AssetFolder)/$($AssetFileName)"

    

    Write-Log "Start upload to: $uri"
    Write-Host -ForegroundColor Green "    Start upload to:      $uri"
    
    $fileSizeGB = [math]::Round((Get-Item $LocalFilePath).Length / 1GB, 2)
    Write-Host "    Upload file size:     $fileSizeGB GB"
    Write-Log  "Upload file size: $fileSizeGB GB"

    $publish = 1
    if($fileSizeGB -lt 2){
        Write-Host "    Upload mode:          Invoke-WebRequest -InFile"
        Write-Log  "Upload mode: Invoke-WebRequest -InFile"

        try{
            $headers = @{
                "X-ApiKey"     = "$Key"
                #"Content-Type" = "application/octet-stream"
            }

            #$bytes = [System.IO.File]::ReadAllBytes($LocalFilePath)

            #Invoke-RestMethod -Uri $uri -Method $Method -Headers $headers -Body $bytes -ErrorAction Stop | Out-Null

            # Stream file directly from disk (supports >2GB)
            Invoke-WebRequest -Uri $uri -Method $Method -Headers $headers -ContentType "application/octet-stream" -InFile $LocalFilePath -UseBasicParsing -ErrorAction Stop | Out-Null
        }
        catch{
            Write-TrackedError "Upload failed: $($_.Exception.Message)"
            Write-Log "ERROR: Upload failed: $($_.Exception.Message)"
            $publish = 0
        }
    }
    else{
        Write-Host "    Upload mode:          HttpClient stream"
        Write-Log  "Upload mode: HttpClient stream"

        $sw = $null
        $handler = $null
        $client = $null
        $fs = $null
        $content = $null
        $request = $null
        $response = $null
        
        try{
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            Add-Type -AssemblyName System.Net.Http

            $handler = New-Object System.Net.Http.HttpClientHandler
            $client  = New-Object System.Net.Http.HttpClient($handler)
            $client.DefaultRequestHeaders.Add("X-ApiKey", $Key)

            $fs = [System.IO.File]::OpenRead($LocalFilePath)
            $content = New-Object System.Net.Http.StreamContent($fs)
            $content.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("application/octet-stream")

            $request = New-Object System.Net.Http.HttpRequestMessage((New-Object System.Net.Http.HttpMethod($Method)), $uri)
            $request.Content = $content

            $response = $client.SendAsync($request).GetAwaiter().GetResult()
            $response.EnsureSuccessStatusCode()

            $sw.Stop()
            Write-Host "    Upload finished in:   $($sw.Elapsed)"
            Write-Log  "Upload finished in: $($sw.Elapsed)"

        }
        catch{
            if ($sw) { $sw.Stop() }
            Write-TrackedError "Upload failed: $($_.Exception.Message)"
            Write-Log "ERROR: Upload failed after $($sw.Elapsed): $($_.Exception.Message)"
            $publish = 0
        }
        finally {
            if ($response) { $response.Dispose() }
            if ($request)  { $request.Dispose() }
            if ($content)  { $content.Dispose() }
            if ($fs)       { $fs.Dispose() }
            if ($client)   { $client.Dispose() }
            if ($handler)  { $handler.Dispose() }
        }
    }

    return $publish
}

function Get-ProGetAssetSha256 {
    param(
        [Parameter(Mandatory)] [string] $FolderPath,     # e.g. "NotepadPlusPlus/NotepadPlusPlus"
        [Parameter(Mandatory)] [string] $FileName,       # e.g. "NotepadPlusPlus_x64_8.8.9.exe"
        [Parameter(Mandatory)] [string] $Key
    )

    $uri = "$ProGetBaseUrl/endpoints/$ProGetAssetDir/metadata/$FolderPath/$FileName"

    $file = Invoke-RestMethod -Uri $uri -Headers @{
        "Accept"   = "application/json"
        "X-ApiKey" = "$Key"
    } -ErrorAction Stop

    Write-Log "SHA256 Hash for file $($FileName): $($file.sha256)"
    return $file.sha256
}

function Set-NuspecVersion {
    param(
        [Parameter(Mandatory)] [string] $NuspecPath,
        [Parameter(Mandatory)] [string] $NewVersion
    )

    $updated = 1
    try{
        [xml]$xml = Get-Content $NuspecPath
        $xml.package.metadata.version = $NewVersion
        $xml.Save($NuspecPath)
    }
    catch{
        $updated = 0
    }

    return $updated
}

function Set-ChecksumsJson {
    param(
        [Parameter(Mandatory)] [string] $ChecksumsPath,
        [Parameter(Mandatory)] [ValidateSet('x64','x86')] [string] $Arch,
        [Parameter(Mandatory)] [string] $Sha
    )

    $obj = Get-Content $ChecksumsPath -Raw | ConvertFrom-Json
    $obj.$Arch = $Sha
    $obj | ConvertTo-Json -Compress | Set-Content $ChecksumsPath -Encoding UTF8
}

function Publish-ChocoPackageToProGet {
    param(
        [Parameter(Mandatory)] [string] $PackageSourceDir,
        [Parameter(Mandatory)] [string] $PushUrl,
        [Parameter(Mandatory)] [string] $Key
    )

    Write-Log "Push current location to: $PackageSourceDir"
    Write-Host "    Push current location to: $PackageSourceDir"
    try{
        Push-Location $PackageSourceDir
    }
    catch{
        Write-Log "ERROR: Could not push current location - $_"
        Write-TrackedError "ERROR: Could not push current location - $_"
    }

    Write-Log "Attempting to create new package and push it to ProGet feed"
    Write-Host -ForegroundColor Green "    Attempting to create new package and push it to ProGet feed"
    try {
        choco pack | Out-Null

        $nupkg = Get-ChildItem -Path $PackageSourceDir -Filter "*.nupkg" |
                 Sort-Object LastWriteTime -Descending |
                 Select-Object -First 1

        if (-not $nupkg) { 
            Write-Log "ERROR: No .nupkg created in $PackageSourceDir - $_" 
            Write-TrackedError "ERROR: No .nupkg created in $PackageSourceDir - $_"
        }

        choco push $nupkg.FullName --source="$PushUrl" --api-key="$Key" --force | Out-Null
        return $nupkg.FullName
    }
    finally {
        Pop-Location
    }
}

function Get-ProGetAssetFolderItems {
    param(
        [Parameter(Mandatory)] [string] $FolderPath  # e.g. "NotepadPlusPlus/NotepadPlusPlus"
    )

    $uri = "$ProGetBaseUrl/endpoints/$ProGetAssetDir/dir/$FolderPath"
    Write-Log "Asset Folder Item URI:    $($uri)"

    $AssetItems = Invoke-RestMethod -Uri $uri -Headers @{
        "Accept"   = "application/json"
        "X-ApiKey" = "$ProGetAssetApiKey"
    } -ErrorAction Stop

    return $AssetItems
}

function Get-ExistingInstallerFromProGetAssets {
    param(
        [Parameter(Mandatory)] [string] $AssetFolderPath,  # e.g. "NotepadPlusPlus/NotepadPlusPlus"
        [Parameter(Mandatory)] [string] $SoftwareName,     # e.g. "NotepadPlusPlus"
        [Parameter(Mandatory)] [string] $Arch,             # e.g. "x64"
        [Parameter(Mandatory)] [string] $Extension         # e.g. "exe"
    )

    $escapedSoftwareName = [regex]::Escape($SoftwareName)
    $extNoDot = $Extension.TrimStart('.').ToLower()

    # List items in folder
    $FolderItems = Get-ProGetAssetFolderItems -FolderPath $AssetFolderPath
 
    if (-not $folderItems) {
        Write-TrackedWarning "No items returned from ProGet directory listing."
        Write-Log "WARNING: No items returned from ProGet directory listing."
        return $null
    }
    

    # Keep only files matching your naming convention
    # Example: NotepadPP_x64_8.8.9.exe
    $hits = foreach ($item in $FolderItems) {
        # ProGet returns fields like "name", "parent", "size", etc.
        $name = $item.name
        
        #Debug
        #Write-Host "DEBUG: name='$name' software='$escapedSoftwareName' arch='$Arch' ext='$extNoDot'"
        
        if (-not $name) { continue }

        if ($name -match "^$escapedSoftwareName" -and
            $name -match "_$([regex]::Escape($Arch))_" -and
            $name.ToLower().EndsWith(".$extNoDot")) {

            # Extract semantic version
            if ($name -match "(\d+(\.\d+){1,3})") {
                $verStr = $Matches[1]
                [PSCustomObject]@{
                    Name       = $name
                    VersionRaw = $verStr              # preserve exact text from filename
                    VersionCmp = [Version]$verStr     # for sorting/comparing
                    Parent     = $item.parent
                    Size       = $item.size
                }
            }
            #Debug
            #Write-Host "DEBUG: name='$name' version='$verStr' parent='$item.parent' size='$item.size'"
        }
        
    }

    if (-not $hits) { 
        return $null 
    }

    # Select latest version
    # $latest = $hits | Sort-Object Version -Descending | Select-Object -First 1
    $latest = $hits | Sort-Object VersionCmp -Descending | Select-Object -First 1

    #Debug
    <#
    Write-Host " Existing Installer Name:   $($latest.Name)"
    $Version    = $latest.Version.ToString()
    Write-Host " Latest Version:            $Version"
    Write-Host " Asset Path:                $($AssetFolderPath)/$($latest.Name)"
    Write-Host " MetaUrl:                   $($ProGetBaseUrl)/endpoints/$($ProGetAssetDir)/metadata/$($AssetFolderPath)/$($latest.Name)"
    Write-Host " ContentUrl:                $($ProGetBaseUrl)/endpoints/$($ProGetAssetDir)/content/$($AssetFolderPath)/$($latest.Name)"
    #>
 
    # Return an object that feels like your previous $existingInstaller
    return [PSCustomObject]@{
        Name         = $latest.Name
        VersionRaw   = $latest.VersionRaw
        VersionCmp   = $latest.VersionCmp.ToString()
        AssetPath    = "$($AssetFolderPath)/$($latest.Name)"
        MetadataUrl  = "$ProGetBaseUrl/endpoints/$ProGetAssetDir/metadata/$AssetFolderPath/$($latest.Name)"
        ContentUrl   = "$ProGetBaseUrl/endpoints/$ProGetAssetDir/content/$AssetFolderPath/$($latest.Name)"
    }

}

function Set-ChocoUrlVariableLine {
    param(
        [Parameter(Mandatory)] [string] $Content,
        [Parameter(Mandatory)] [ValidateSet('url','url64')] [string] $VarName,
        [Parameter(Mandatory)] [string] $NewUrl
    )

    # Build regex safely without $$ expansion
    $pattern = '(?m)^(\s*\$' + [regex]::Escape($VarName) + '\s*=\s*)(?:''[^'']*''|"[^"]*"|[^\r\n#]+)?(\s*(#.*)?)$'


    return [regex]::Replace($Content, $pattern, {
        param($m)
        "$($m.Groups[1].Value)'$NewUrl'$($m.Groups[2].Value)"
    })
}

function Update-ChocoInstallationScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $ToolsDir,                  # e.g. E:\Choco\Packages\NotepadPlusPlus\tools
        [Parameter(Mandatory)] [string] $ProGetBaseUrl,             # e.g. http://PSC-SWREPO1:8624
        [Parameter(Mandatory)] [string] $ProGetAssetDir,            # e.g. choco-assets
        [Parameter(Mandatory)] [string] $AssetFolderPath,           # e.g. NotepadPlusPlus/NotepadPlusPlus
        [Parameter(Mandatory)] [string] $InstallerFileName,         # e.g. NotepadPlusPlus_x64_8.9.exe
        [Parameter(Mandatory)] [string] $FileType,                  # e.g. exe, msi etc.
        [Parameter(Mandatory)] [string] $Arch,                      # e.g. x64, x86 
        [Parameter(Mandatory)] [string] $Sha                        
    )

    # Validate FileType at runtime because ValidateSet requires compile-time constants
    if (-not ($installerTypeToExtension.Values -contains $FileType)) {
        throw "Invalid FileType '$FileType'. Allowed values: $($installerTypeToExtension.Values -join ', ')"
    }

    # Validate Architecture at runtime because ValidateSet requires compile-time constants
    if (-not ($installerArchType.Values -contains $Arch)) {
        throw "Invalid Architecture '$Arch'. Allowed values: $($installerArchType.Values -join ', ')"
    }

    $assetUrl = "$ProGetBaseUrl/endpoints/$ProGetAssetDir/content/$AssetFolderPath/$InstallerFileName"
    
    #DEBUG
    <#
    Write-Host "$ToolsDir"
    Write-Host "$ProGetBaseUrl"
    Write-Host "$ProGetAssetDir"
    Write-Host "$AssetFolderPath"
    Write-Host "$InstallerFileName"
    Write-Host "$FileType"
    Write-Host "$Arch"
    Write-Host "$Sha"
    Write-Host "$assetUrl"
    #>

    Write-Log "ToolsDir: $ToolsDir | FileName: $InstallerFileName | Hash: $Sha | AssetUrl: $assetUrl"


    $scriptPath = Join-Path $ToolsDir "chocolateyinstall.ps1"
    if (-not (Test-Path $scriptPath)) {
        throw "chocolateyinstall.ps1 not found: $scriptPath"
    }

    

    $content = Get-Content $scriptPath -Raw

    # Always update fileType in packageArgs
    $content = [regex]::Replace(
        $content,
        "(?m)^\s*fileType\s*=\s*'.*?'.*$",
        "  fileType      = '$FileType' #only one of these: exe, msi, msu"
    )

    # Keep checksum type consistent (optional but recommended)
    $content = [regex]::Replace(
        $content,
        "(?m)^\s*checksumType\s*=\s*'.*?'.*$",
        "  checksumType  = 'sha256' #default is sha256"
    )
    $content = [regex]::Replace(
        $content,
        "(?m)^\s*checksumType64\s*=\s*'.*?'.*$",
        "  checksumType64= 'sha256' #default is checksumType"
    )
    
    if ($Arch -eq 'x64') {
        # Update $url64 variable
        <#
        $content = [regex]::Replace(
            $content,
            "(?m)^\s*\$url64\s*=\s*'.*?'.*$",
            "`$url64      = '$assetUrl'"
        )
        #>
        $content = Set-ChocoUrlVariableLine -Content $content -VarName 'url64' -NewUrl $assetUrl

        # Ensure packageArgs uses $url64
        $content = [regex]::Replace(
            $content,
            "(?m)^\s*url64bit\s*=\s*(?:\$\w+|'.*?')\s*$",
            "  url64bit      = `$url64"
        )

        # Update checksums (keep checksum + checksum64 same for x64-only packages)
        $content = [regex]::Replace(
            $content,
            "(?m)^\s*checksum64\s*=\s*'.*?'\s*$",
            "  checksum64    = '$Sha'"
        )
        $content = [regex]::Replace(
            $content,
            "(?m)^\s*checksum\s*=\s*'.*?'\s*$",
            "  checksum      = '$Sha'"
        )
    }
    elseif ($Arch -eq 'x86') {
        # Update $url variable
        <#
        $content = [regex]::Replace(
            $content,
            "(?m)^\s*\$url\s*=\s*'.*?'.*$",
            "`$url        = '$assetUrl'"
        )
        #>
        $content = Set-ChocoUrlVariableLine -Content $content -VarName 'url' -NewUrl $assetUrl

        # Ensure packageArgs uses $url (if present)
        $content = [regex]::Replace(
            $content,
            "(?m)^\s*url\s*=\s*(?:\$\w+|'.*?')\s*$",
            "  url           = `$url"
        )

        # Update checksum (x86)
        $content = [regex]::Replace(
            $content,
            "(?m)^\s*checksum\s*=\s*'.*?'\s*$",
            "  checksum      = '$Sha'"
        )
    }
    $updated = 1
    try{
        Set-Content -Path $scriptPath -Value $content -Encoding UTF8
    }
    catch{
        throw "Chocolatey 'install script' content not updated."
        $updated = 0
    }

    return $updated
}

function Convert-NameForProGetPath {
    param(
        [Parameter(Mandatory)] [string] $Name
    )

    if($Name -match '\+'){
        $Name = $Name -replace '\+', 'Plus'
    }
    if($Name -match '\='){
        $Name = $Name -replace '\=', ''
    }
    if($Name -match '\#'){
        $Name = $Name -replace '\#', ''
    }

    return $Name
}

# Fix "FileName = installer / download" cases
function Ensure-ResolvedFileName {
    param(
        [Parameter(Mandatory)] $Intent,
        [Parameter(Mandatory)] $Software
    )

    # If filename looks useless or has no extension, resolve via web
    $needsResolve = $false

    if ([string]::IsNullOrWhiteSpace($Intent.FileName)) { $needsResolve = $true }
    elseif ($Intent.FileName -in @('download','installer')) { $needsResolve = $true }
    elseif ([IO.Path]::GetExtension($Intent.FileName) -eq '') { $needsResolve = $true }

    if (-not $needsResolve) { return $Intent }

    $info = Resolve-DownloadInfo -Url $Intent.InstallerUrl -SoftwareName $Software.SoftwareName -PreferredExtension $Software.PreferredExtension
    if ($info -and $info.FileName) {
        $Intent.FileName = $info.FileName
        $Intent.Extension = [IO.Path]::GetExtension($info.FileName)
        $Intent.InstallerUrl = $info.DownloadUrl  # important: store final resolved URL for download
    }

    return $Intent
}




###
### Helper Functions
###
# HELPER: Normalize semantic version safely
<#
function Convert-ToSemVerString {
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "Version value is empty or whitespace."
    }

    # Accept X.Y, X.Y.Z, X.Y.Z.W
    if ($Value -match '(\d+(\.\d+){1,3})') {
        return ([version]$matches[1]).ToString()
    }

    throw "Could not parse semantic version from '$Value'"
}
#>

# HELPER: Normalize semantic version safely
function Convert-ToVersionObject {
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "Version value is empty or whitespace."
    }

    # Accept X.Y, X.Y.Z, X.Y.Z.W
    if ($Value -match '(\d+(\.\d+){1,3})') {
        return [version]$matches[1]
    }

    throw "Could not parse semantic version from '$Value'"
}

# HELPER: Build your deterministic final file name
function New-EnterpriseInstallerFileName {
    param(
        [Parameter(Mandatory)] $Software,
        [Parameter(Mandatory)] [string] $Version,
        [Parameter(Mandatory)] [string] $Extension
    )

    $name = $Software.SoftwareName

    if (-not [string]::IsNullOrWhiteSpace($Software.SubName1)) { $name = "$name`_$($Software.SubName1)" }
    if (-not [string]::IsNullOrWhiteSpace($Software.SubName2)) { $name = "$name`_$($Software.SubName2)" }

    # Your path conversion rules (optional)
    $name = Convert-NameForProGetPath $name

    return "$name`_$($Software.Arch)_$Version$Extension"
}

# HELPER: Extract and copy 'tools' from a .nupkg | specially fir 'chocolatey' itself!
function Update-ChocolateyPackage {
    param(
        [Parameter(Mandatory)] [string] $NupkgPath,          # downloaded .nupkg
        [Parameter(Mandatory)] [string] $PackageSourcePath,  # e.g. E:\Choco\Packages\Chocolatey\Chocolatey
        [Parameter(Mandatory)] [string] $WorkingRoot         # e.g. E:\ChocoManage\temp\Downloads
    )

    $targetToolsDir = Join-Path $PackageSourcePath "tools"
    if (-not (Test-Path $targetToolsDir)) {
        throw "Target tools directory not found: $targetToolsDir"
    }

    # temp extract folder (unique)
    $extractDir = Join-Path $WorkingRoot ("_extract_choco_" + [guid]::NewGuid().ToString("N"))
    $stagingDir = Join-Path $extractDir "staging"
    #$zipPath    = Join-Path $extractDir "package.zip"   # temp renamed copy

    try {
        New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
        New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null

        Write-Host "    Extracting nupkg to:    $extractDir"
        Write-Log  "Extracting nupkg to: $extractDir"

        # Expand-Archive only supports .zip extension, so create a temp .zip copy
        #Copy-Item -Path $NupkgPath -Destination $zipPath -Force | Out-Null
        #Expand-Archive -Path $NupkgPath -DestinationPath $extractDir -Force | Out-Null
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($NupkgPath, $extractDir)

        # Most nupkgs have a root 'tools' folder
        $extractedToolsDir = Join-Path $extractDir "tools"
        if (-not (Test-Path $extractedToolsDir)) {
            throw "No 'tools' folder found inside nupkg: $NupkgPath"
        }

        # Stage new tools content first (safer than deleting target immediately)
        Copy-Item -Path (Join-Path $extractedToolsDir '*') -Destination $stagingDir -Recurse -Force

        # Clean existing target tools content (but keep the tools folder itself)
        Write-Host "    Replacing contents of:  $targetToolsDir"
        Write-Log  "Replacing contents of: $targetToolsDir"

        # Remove current contents, keep folder
        Get-ChildItem -Path $targetToolsDir -Force -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction Stop
        }

        # Copy staged content into target tools
        Copy-Item -Path (Join-Path $stagingDir '*') -Destination $targetToolsDir -Recurse -Force | Out-Null

        Write-Host -ForegroundColor Green "    Chocolatey tools folder replaced successfully"
        Write-Log  "Chocolatey tools folder replaced successfully"

        return $true
    }
    catch {
        Write-TrackedError "Chocolatey tools extraction/copy failed: $_"
        Write-Log "ERROR: Chocolatey tools extraction/copy failed: $_"
        return $false
    }
    finally {
        if (Test-Path $extractDir) {
            try { 
                Remove-Item -Path $extractDir -Recurse -Force 
            } 
            catch {
                Write-TrackedWarning "Removing from arfticat extraction directory failed: $_"
                Write-Log "WARNING: Removing from arfticat extraction directory failed: $_"
            }
        }
    }

}

# HELPER: Get current Office Version
function Get-OfficeVersion {
    param(
        [Parameter(Mandatory)] [string] $VersionFile
    )
    
    
    if(Test-Path $VersionFile){

        try {            
            $obj = Get-Content $VersionFile -Raw | ConvertFrom-Json
            #Write-Host "    Current Office version is: $($obj.version)" -ForegroundColor Magenta
            #Write-Log "Current Office version is: $($obj.version)"
            return $obj.version
        }
        catch {
            Write-TrackedWarning "Office version.json read failed for '$($VersionFile)': $_"
            Write-Log "WARNING: Office version.json read failed for '$($VersionFile)': $_"
            return $null
        }
    }
    else{
        Write-TrackedWarning "No version.json file found."
        Write-Log "WARNING: No version.json file found."
        return $null
    }
}

# HELPER: Set Office Version
function Set-OfficeVersion {
    param(
        [Parameter(Mandatory)] [string] $VersionFile,
        [Parameter(Mandatory)] [string] $Version
    )
    
    $obj = Get-Content $VersionFile -Raw | ConvertFrom-Json
    $obj.version = $Version
    $obj | ConvertTo-Json -Compress | Set-Content $VersionFile -Encoding UTF8

}

# HELPER: Get-PackageID Full SoftwareName
function Get-PackageId {
    param(
        [Parameter(Mandatory)] $Software
    )

    $packageId = $Software.SoftwareName

    if (-not [string]::IsNullOrWhiteSpace($Software.SubName1)) {
        $packageId += $Software.SubName1
    }
    if (-not [string]::IsNullOrWhiteSpace($Software.SubName2)) {
        $packageId += $Software.SubName2
    }

    return (Convert-NameForProGetPath $packageId)
}

# HELPER: Get-Software Displayname
function Get-SoftwareDisplayName {
    param(
        [Parameter(Mandatory)] $Software
    )

    $name = $Software.SoftwareName

    if (-not [string]::IsNullOrWhiteSpace($Software.SubName1)) {
        $name += $Software.SubName1
    }
    if (-not [string]::IsNullOrWhiteSpace($Software.SubName2)) {
        $name += $Software.SubName2
    }

    return $name
}




###
### Base PipeLine
###
function Invoke-EnterprisePackageUpdate {
    param(
        [Parameter(Mandatory)] [pscustomobject] $Software,
        [Parameter(Mandatory)] [pscustomobject] $Paths,
        [Parameter(Mandatory)] [pscustomobject] $Intent,
        [Parameter(Mandatory)] [string] $DownloadPath
    )

    # 1) Find existing in ProGet assets
    # 2) Compare versions
    # 3) Acquire installer (download or local picked)
    # 4) Handle nested zip extraction (if Intent.Nested)
    # 5) Copy to package tools folder
    # 6) Upload to ProGet assets
    # 7) Fetch SHA256 from ProGet metadata
    # 8) Update nuspec/checksums/install script
    # 9) pack + push
    # 10) cleanup

    $dwnFile = 0
    $pubAssetFile = 0
    $updNuspec = 0
    $updScript = 0
    $nupkgPath = $null

    $proGetFolder = $Paths.ProGetAssetRelativePath
    $localPkgPath = $Paths.LocalStoragePath

    # --- normalize version ---
    #$availableVersion = Convert-ToSemVerString -Value $Intent.Version

    # --- preserve source version text for naming/display ---
    $availableVersionRaw = [string]$Intent.Version
    if ([string]::IsNullOrWhiteSpace($availableVersionRaw)) {
        Write-TrackedError "Intent.Version is empty."
        Write-Log "ERROR: Intent.Version is empty."
    }
    # --- parse comparable version separately ---
    $availableVersionCmp = Convert-ToVersionObject -Value $availableVersionRaw

    # --- OfficeCdn versioning ---
    if ($Intent.SourceType -eq 'OfficeCdn') {
        $versions = Join-Path $localPkgPath "tools\version.json"
        if (-not (Test-Path $versions)) {
            Write-Log "OfficeCdn: No '$versions' file found. Creating one..."
@"
{
  "version": ""
}
"@ | Set-Content -Path $versions -Encoding UTF8
        }

        $currentOfficeVer = Get-OfficeVersion -VersionFile $versions
        if ($currentOfficeVer) {
            Write-Host "    Current Office ver:   $currentOfficeVer (version.json)"
            if (-not $Force -and ([version]$currentOfficeVer -eq $availableVersionCmp)) {
                Write-Host -ForegroundColor Magenta "    PIPELINE: up-to-date (office json) -> skip"
                Write-Log "PIPELINE: up-to-date (office json) -> skip"
                return
            }
            else{
                Set-OfficeVersion -VersionFile $versions -Version $Intent.Version
                Write-Log "OfficeCdn: New Office version set to: $currentOfficeVer"
            }
        }
        else{
            Set-OfficeVersion -VersionFile $versions -Version $Intent.Version
            Write-Log "OfficeCdn: New Office version set to: $currentOfficeVer"
        }
    }

    # --- determine extension to use for naming ---
    # Prefer the CSV PreferredExtension (enterprise controlled),
    # except when nested ZIP (outer is zip, inner is preferred extension)
    $preferredExt = $Software.PreferredExtension
    if ([string]::IsNullOrWhiteSpace($preferredExt)) {
        throw "PreferredExtension missing for $($Software.SoftwareName)"
    }

    $outerExt = $preferredExt
    if ($Intent.Nested -and $Intent.Nested.RelativeFilePath) {
        $outerExt = ".zip"
    }
    elseif ($Intent.Extension) {
        # if Intent has a usable extension, keep it, else use preferred
        if ($Intent.Extension.StartsWith('.')) { $outerExt = $Intent.Extension } else { $outerExt = ".$($Intent.Extension)" }
    }

    # --- build final deterministic filename ---
    $finalFileName = New-EnterpriseInstallerFileName -Software $Software -Version $availableVersionRaw -Extension $outerExt
    $downloadTarget = Join-Path $DownloadPath $finalFileName

    Write-Host "  === Pipeline ==="
    Write-Host "    SourceType:           $($Intent.SourceType)"
    #Write-Host "    Avail version Raw:    $availableVersionRaw"
    #Write-Host "    Avail version Cmp:    $availableVersionCmp"
    Write-Host "    ProGet folder:        $proGetFolder"
    Write-Host "    Local package path:   $localPkgPath"
    Write-Host "    Final filename:       $finalFileName"
    Write-Log  "PIPELINE: $($Software.Publisher) | $($Software.SoftwareName) source=$($Intent.SourceType) ver=$availableVersionRaw file=$finalFileName"

    # --- find existing installer in ProGet ---
    $existingInstaller = $null
    try {
        $existingInstaller = Get-ExistingInstallerFromProGetAssets `
            -AssetFolderPath $proGetFolder `
            -SoftwareName (Convert-NameForProGetPath $Software.SoftwareName) `
            -Arch $Software.Arch `
            -Extension $preferredExt
    }
    catch {
        Write-TrackedWarning "Could not query existing installer from ProGet for $($Software.SoftwareName): $_"
        Write-Log "WARNING: ProGet existing installer query failed: $_"
    }

    $shouldUpdate = $true
    if ($existingInstaller -and $existingInstaller.VersionCmp) {
        try {
            $existingVercmp    = [version]$existingInstaller.VersionCmp
            $availVerCmp       = [version]$availableVersionCmp

            Write-Host "    Current version Raw:  $($existingInstaller.VersionRaw)"
            Write-Host "    Current version Cmp:  $existingVerCmp"
            Write-Host "    Avail version Raw:    $availableVersionRaw"
            Write-Host "    Avail version Cmp:    $availVerCmp"

            if (-not $Force -and $existingVerCmp -eq $availVerCmp) {
                Write-Host -ForegroundColor Magenta "    Already up to date. Skipping."
                Write-Log "PIPELINE: up-to-date -> skip"
                $shouldUpdate = $false
            }

            if ($Force) {
                Write-Host -ForegroundColor Yellow "    FORCE enabled -> running update pipeline anyway."
                Write-Log "PIPELINE: FORCE -> override version skip"
            }
        }
        catch {
            # If existing version is weird, fall back to filename compare later
            Write-TrackedWarning "Version compare failed, will fall back to filename compare: $_"
        }
    }

    if (-not $shouldUpdate) { 
        return 
    }
    else{
        # --- acquire installer artifact ---
        $artifactPath = $null

        #if ($Intent.SourceType -eq 'Local' -and $Intent.LocalPickedFile) {
        if (($Intent.SourceType -eq 'Local' -or $Intent.SourceType -eq 'OfficeCdn') -and $Intent.LocalPickedFile -and (Test-Path $Intent.LocalPickedFile)) {
            # Copy local picked file to deterministic target filename
            try{
                Copy-Item -Path $Intent.LocalPickedFile -Destination $downloadTarget -Force | Out-Null
                $artifactPath = $downloadTarget
                $dwnFile = 1   # LOCAL source was successfully acquired
                Write-Host "    Using local file:     $($Intent.LocalPickedFile)"
                Write-Host "    Copied to:            $artifactPath"
                Write-Log  "LOCAL acquire success: '$($Intent.LocalPickedFile)' -> '$artifactPath'"
            }
            catch{
                $dwnFile = 0
                Write-TrackedError "LOCAL acquire failed: $_"
                Write-Log "ERROR: LOCAL acquire failed: $_"
                throw
            }
        }
        else {
            # Download remote to deterministic filename
            if (-not $Intent.InstallerUrl) {
                throw "Intent.InstallerUrl missing for non-local source ($($Intent.SourceType))"
            }

            Write-Host "    Downloading from:     $($Intent.InstallerUrl)"
            Write-Host "    Downloading to:       $downloadTarget"
            $dwnFile = Start-DownloadInstallerFile -Url $Intent.InstallerUrl -DestinationPath $downloadTarget
            $artifactPath = $downloadTarget
        }

        # --- nested ZIP extraction (extract only one file) ---
        if ($Intent.Nested -and $Intent.Nested.RelativeFilePath) {

            $relativePath = $Intent.Nested.RelativeFilePath
            $leafName = Split-Path $relativePath -Leaf

            $extractedPath = Join-Path $DownloadPath $leafName

            Write-Host -ForegroundColor Magenta "    Nested ZIP detected. Extracting only: $relativePath"
            Write-Host -ForegroundColor Magenta "    Extract to:            $extractedPath"

            try {
                Add-Type -AssemblyName System.IO.Compression.FileSystem

                $zip = [System.IO.Compression.ZipFile]::OpenRead($artifactPath)
                $entry = $zip.Entries | Where-Object { $_.FullName -eq $relativePath } | Select-Object -First 1

                if (-not $entry) {
                    $zip.Dispose()
                    throw "Nested file '$relativePath' not found in zip."
                }

                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $extractedPath, $true)
                $zip.Dispose()

                # Now the extracted file becomes the actual artifact we deploy/upload/package
                $artifactPath = $extractedPath

                # Update deterministic filename for inner artifact (keep enterprise naming!)
                $innerExt = [IO.Path]::GetExtension($leafName)
                if (-not $innerExt) { $innerExt = $preferredExt }

                $finalInnerName = New-EnterpriseInstallerFileName -Software $Software -Version $availableVersionRaw -Extension $innerExt
                $finalInnerPath = Join-Path $DownloadPath $finalInnerName

                Copy-Item -Path $artifactPath -Destination $finalInnerPath -Force | Out-Null
                $artifactPath = $finalInnerPath

                Write-Host -ForegroundColor Magenta "    Extracted and renamed to: $artifactPath"
            }
            catch {
                Write-TrackedError "Nested extraction failed: $_"
                Write-Log "ERROR: Nested extraction failed: $_"
                throw
            }
        }


        # --- publish to ProGet assets ---
        if ($WhatIfPublish) {
            Write-Host -ForegroundColor Yellow "    WHATIFPUBLISH enabled -> skipping ProGet upload and choco push."
            Write-Log "WHATIFPUBLISH enabled -> skipping ProGet upload and choco push."
        }
        <#
        Only if a new chocolatey version is available.
        #>
        <#
        elseif($($Software.SoftwareName) -eq "Chocolatey"){
            Write-Host -ForegroundColor Magenta "
    You are about to update Chocolatey itself -> skipping ProGet upload and choco push.

    This is a pre-configured '.nupkg' package of chocolatey. 
    Extract and copy the 'tools' directory from the new package and replace your existing 'tools' directory 
    inside your existing package structure."

            Write-Host "    Path to your 'tools' directory is:    $($localPkgPath)\tools"

            $assetFileName = Split-Path $artifactPath -Leaf

            # --- fetch sha256 from ProGet metadata ---
            $sha = Get-ProGetAssetSha256 -FolderPath $proGetFolder -FileName $assetFileName -Key $ProGetAssetApiKey
            if (-not $sha) { 
                Write-TrackedError "Could not fetch SHA256 from ProGet for $assetFileName"
                Write-Log "ERROR: Could not fetch SHA256 from ProGet for $assetFileName"
            }
            
            #$packageId = Convert-NameForProGetPath $Software.SoftwareName
            $packageId = Get-PackageId -Software $Software
            $nuspec    = Join-Path $localPkgPath "$($packageId).nuspec"
            $checksums = Join-Path $localPkgPath "tools\checksums.json"

            if (-not (Test-Path $checksums)) {
                @"
{
  "x64": "",
  "x86": ""
}
"@ | Set-Content -Path $checksums -Encoding UTF8
            }

            $updNuspec = Set-NuspecVersion -NuspecPath $nuspec -NewVersion $availableVersionRaw
            Set-ChecksumsJson -ChecksumsPath $checksums -Arch $Software.Arch -Sha $sha

        }
        #>
        elseif ($Software.SoftwareName -eq "Chocolatey") {
            Write-Host -ForegroundColor Magenta "    Special package handling for Chocolatey (.nupkg): extract and replace 'tools' folder"

            # 1) Extract downloaded nupkg and replace local package source tools\ contents
            $chocoToolsUpdated = Update-ChocolateyPackage `
                -NupkgPath $artifactPath `
                -PackageSourcePath $localPkgPath `
                -WorkingRoot $DownloadPath

            if (-not $chocoToolsUpdated) {
                Write-TrackedError "Chocolatey tools replacement failed"
                Write-Log "ERROR: Chocolatey tools replacement failed"
                throw "Chocolatey tools replacement failed"
            }

            # 2) Upload the downloaded nupkg asset to ProGet (same as normal flow)
            $assetFileName = Split-Path $artifactPath -Leaf

            if ($WhatIfPublish) {
                Write-Host -ForegroundColor Yellow "    WHATIFPUBLISH enabled -> skipping ProGet upload and choco push."
                Write-Log  "WHATIFPUBLISH enabled -> skipping ProGet upload and choco push."
            }
            else {
                $pubAssetFile = Publish-ProGetAssetFile `
                    -LocalFilePath $artifactPath `
                    -AssetFolder $proGetFolder `
                    -AssetFileName $assetFileName `
                    -Key $ProGetAssetApiKey `
                    -Method POST

                if (-not $pubAssetFile -or $pubAssetFile -eq 0) {
                    Write-TrackedError "Upload to ProGet Assets failed for $assetFileName"
                    Write-Log "ERROR: Upload to ProGet Assets failed for $assetFileName"
                }

                # 3) Fetch SHA256 from ProGet metadata (same as normal flow)
                $sha = Get-ProGetAssetSha256 -FolderPath $proGetFolder -FileName $assetFileName -Key $ProGetAssetApiKey
                if (-not $sha) {
                    Write-TrackedError "Could not fetch SHA256 from ProGet for $assetFileName"
                    Write-Log "ERROR: Could not fetch SHA256 from ProGet for $assetFileName"
                }

                # 4) Update nuspec/checksums (install script usually comes from extracted tools and should already be correct)
                #$packageId = Convert-NameForProGetPath $Software.SoftwareName
                $packageId = Get-PackageId -Software $Software
                $nuspec    = Join-Path $localPkgPath "$($packageId).nuspec"
                $checksums = Join-Path $localPkgPath "tools\checksums.json"

                if (-not (Test-Path $checksums)) {
@"
{
  "x64": "",
  "x86": ""
}
"@ | Set-Content -Path $checksums -Encoding UTF8
                }

                $updNuspec = Set-NuspecVersion -NuspecPath $nuspec -NewVersion $availableVersionRaw
                Set-ChecksumsJson -ChecksumsPath $checksums -Arch $Software.Arch -Sha $sha

                # 5) Pack + push updated internal package
                $nupkgPath = Publish-ChocoPackageToProGet `
                    -PackageSourceDir $localPkgPath `
                    -PushUrl $ProGetChocoPushUrl `
                    -Key $ProGetFeedApiKey

                if (-not $nupkgPath) {
                    Write-TrackedError "choco pack/push failed for $packageId"
                    Write-Log "ERROR: choco pack/push failed for $packageId"
                }
            }
            
        }
        else {
            # --- remove old installer file from local package tools (if exists) ---
            if ($existingInstaller -and $existingInstaller.Name) {
                $currentLocalFile = Join-Path (Join-Path $localPkgPath "tools") $existingInstaller.Name
                
                if (Test-Path $currentLocalFile) {
                    try{
                        Remove-File -Path $currentLocalFile
                    }
                    catch{
                        Write-TrackedError "Removing of old installer file failed."
                        Write-Log "ERROR: Removing of old installer file failed."
                    }
                }
                else{
                    Write-TrackedWarning "Existing installer file not found."
                    Write-Log "WARNING: Existing installer file not found."
                }
            }
            
            <# Possible Improvement for the future
            if ($existingInstaller -and $existingInstaller.Name) {
                $toolsDir = Join-Path $localPkgPath "tools"
                $prefix   = "{0}_{1}_" -f $Software.SoftwareName, $Software.Architecture
                $pattern  = "$prefix*$($Software.Installer)"

                $currentLocalFile = Join-Path $toolsDir $existingInstaller.Name
                
                if (Test-Path $currentLocalFile) {

                    try{
                        Get-ChildItem -Path $toolsDir -File -ErrorAction SilentlyContinue |
                            Where-Object { $_.Name -like $pattern -and $_.Name -ne $finalFileName } |
                            ForEach-Object {
                                Write-Host "    Removing old installer: $($_.Name)"
                                Remove-File -Path $_.FullName
                            }
                    }
                    catch{
                        Write-TrackedError "Removing of old installer file failed."
                        Write-Log "ERROR: Removing of old installer file failed."
                    }
                }
                else{
                    Write-TrackedWarning "Existing installer file not found."
                    Write-Log "WARNING: Existing installer file not found."
                }
            }
            #>

            # --- copy artifact into local package tools folder ---
            Copy-File -Source $artifactPath -Dest (Join-Path $localPkgPath "tools")

            $assetFileName = Split-Path $artifactPath -Leaf

            <# DEBUG #>
            #Write-Host -ForegroundColor Magenta "DEBUG: entering Publish-ProGetAssetFile"
            #Write-Log "DEBUG: entering Publish-ProGetAssetFile"
            <# DEBUG #>

            $pubAssetFile = Publish-ProGetAssetFile -LocalFilePath $artifactPath -AssetFolder $proGetFolder -AssetFileName $assetFileName -Key $ProGetAssetApiKey -Method POST
            if (-not $pubAssetFile -or $pubAssetFile -eq 0) {
                Write-TrackedError "Upload to ProGet Assets failed for $assetFileName"
                Write-Log "ERROR: Upload to ProGet Assets failed for $assetFileName"
            }

            # --- fetch sha256 from ProGet metadata ---
            $sha = Get-ProGetAssetSha256 -FolderPath $proGetFolder -FileName $assetFileName -Key $ProGetAssetApiKey
            if (-not $sha) { 
                Write-TrackedError "Could not fetch SHA256 from ProGet for $assetFileName"
                Write-Log "ERROR: Could not fetch SHA256 from ProGet for $assetFileName"
            }

            # --- update nuspec/checksums/install script ---
            #$packageId = Convert-NameForProGetPath $Software.SoftwareName
            $packageId = Get-PackageId -Software $Software
            $nuspec    = Join-Path $localPkgPath "$($packageId).nuspec"
            $checksums = Join-Path $localPkgPath "tools\checksums.json"

            if (-not (Test-Path $checksums)) {
                @"
{
  "x64": "",
  "x86": ""
}
"@ | Set-Content -Path $checksums -Encoding UTF8
            }

            $updNuspec = Set-NuspecVersion -NuspecPath $nuspec -NewVersion $availableVersionRaw
            Set-ChecksumsJson -ChecksumsPath $checksums -Arch $Software.Arch -Sha $sha

            
            $fileType = ([IO.Path]::GetExtension($assetFileName)).TrimStart('.').ToLower()
            $updScript = Update-ChocoInstallationScript `
                -ToolsDir (Join-Path $localPkgPath "tools") `
                -ProGetBaseUrl $ProGetBaseUrl `
                -ProGetAssetDir $ProGetAssetDir `
                -AssetFolderPath $proGetFolder `
                -InstallerFileName $assetFileName `
                -FileType $fileType `
                -Arch $Software.Arch `
                -Sha $sha

            # --- pack + push ---
            $nupkgPath = Publish-ChocoPackageToProGet -PackageSourceDir $localPkgPath -PushUrl $ProGetChocoPushUrl -Key $ProGetFeedApiKey
            if (-not $nupkgPath) {
                Write-TrackedError "choco pack/push failed for $packageId"
                Write-Log "ERROR: choco pack/push failed for $packageId"
            }
        }

        # --- cleanup download artifacts (optional) ---
        try {
            if (Test-Path $downloadTarget) { 
                Remove-File -Path $downloadTarget 
            }
            if ($Intent.Nested -and $Intent.Nested.RelativeFilePath) {
                # remove extracted leaf if still present (we renamed to enterprise name anyway)
                $leaf = Split-Path $Intent.Nested.RelativeFilePath -Leaf
                $leafPath = Join-Path $DownloadPath $leaf

                if (Test-Path $leafPath) { 
                    Remove-File -Path $leafPath 
                }
            }
        } catch { 
            Write-TrackedWarning "Removing of artifacts failed. You need to do the cleanup by yourself."
            Write-Log "WARNING: Removing of artifacts failed. You need to do the cleanup by yourself."
        }

        # --- print summary of actual task ---
        Write-Host -ForegroundColor Cyan "  === Pipeline Summary ==="
        Write-Log "=== Pipeline Summary ==="

        $acquireLabel = if ($Intent.SourceType -eq 'Local' -or $Intent.SourceType -eq 'OfficeCdn' ) { "provided" } else { "downloaded" }
        
        if($dwnFile -eq 1){
            Write-Host -ForegroundColor Green "    New Software $acquireLabel successfully"
            Write-Log "New Software $acquireLabel successfully"
        }
        else{
            Write-Host -ForegroundColor Red "    New Software $acquireLabel failed"
            Write-Log "New Software $acquireLabel failed"
        }
        if (-not $WhatIfPublish) { # -and (-not $($Software.SoftwareName) -eq "Chocolatey")
            if($pubAssetFile -eq 1){
                Write-Host -ForegroundColor Green "    New File published successfully in ProGet Assets"
                Write-Log "New File published successfully in ProGet Assets"
            }
            else{
                Write-Host -ForegroundColor Red "    New File publish failed in ProGet Assets"
                Write-Log "New File publish failed in ProGet Assets"
            }
            if($updNuspec -eq 1){
                Write-Host -ForegroundColor Green "    Chocolatey 'nuspec' file updated successfully"
                Write-Log "Chocolatey 'nuspec' file updated successfully"
            }
            else{
                Write-Host -ForegroundColor Red "    Chocolatey 'nuspec' file update failed"
                Write-Log "Chocolatey 'nuspec' file update failed"
            }
            if($updScript -eq 1){
                Write-Host -ForegroundColor Green "    Chocolatey 'install script' file updated successfully"
                Write-Log "Chocolatey 'install script' file updated successfully"
            }
            elseif($($Software.SoftwareName) -eq "Chocolatey"){
                Write-Host -ForegroundColor Magenta "    Chocolatey 'install script' file update skipped"
                Write-Log "Chocolatey 'install script' file update skipped"
            }
            else{
                Write-Host -ForegroundColor Red "    Chocolatey 'install script' file update failed"
                Write-Log "Chocolatey 'install script' file update failed"
            }
            if($nupkgPath){
                Write-Host -ForegroundColor Green "    Chocolatey package created and pushed successfully"
                Write-Log "Chocolatey package created and pushed successfully"
            }
            else{
                Write-Host -ForegroundColor Red "    Chocolatey package creation and push failed"
                Write-Log "Chocolatey package creation and push failed"
            }
        }

        $displayName = Get-SoftwareDisplayName -Software $Software
        Write-Host -ForegroundColor Green "    Updated successfully: $($displayName) -> $availableVersionRaw"
        Write-Log "PIPELINE: success $displayName -> $availableVersionRaw"
    }
}





###
### Start of script
###
Write-Log "=== Starting progress... ==="
Write-Log "Checking PowerShell Module 'powershell-yaml'"
if (-not (Get-Module -Name "powershell-yaml")) {
    Write-TrackedWarning "PowerShell Module 'powershell-yaml' not found."
    Write-Log "WARNING: PowerShell Module 'powershell-yaml' not found."
    Write-Log "Check if PowerShell Module 'powershell-yaml' is available."

    if (Get-Module -ListAvailable -Name "powershell-yaml") {
        Write-Log "PowerShell Mdule 'powershell-yaml' available. Trying to import."

        try{
            Import-Module powershell-yaml
        }
        catch {
            Write-TrackedError "PowerShell Module 'powershell-yaml' can not be imported - $_"
            Write-Log "ERROR: PowerShell Module 'powershell-yaml' can not be imported - $_"
        }
        finally {
            Write-Host -ForegroundColor Cyan "PowerShell Module 'powershell-yaml' imported."
        }
    } else {
        Write-Log "PowerShell Mdule 'powershell-yaml' not available. Trying to install and import it."
        try {
            Install-Module powershell-yaml -Scope CurrentUser -Force -ErrorAction Stop
            Import-Module powershell-yaml
        } catch {
            #Write-Error "Failed to install the 'powershell-yaml' module. $_"
            Write-TrackedError "Failed to install the 'powershell-yaml' module. $_"
            Write-Log "ERROR: Failed to install the 'powershell-yaml' module. $_"
        }
        finally {
            Write-Host -ForegroundColor Cyan "PowerShell Module 'powershell-yaml' installed and imported."
        }
    }
}


Write-Host -ForegroundColor Cyan "
    +----+ +----+     
    |####| |####|     
    |####| |####|       WW   WW II NN   NN DDDDD   OOOOO  WW   WW  SSSS
    +----+ +----+       WW   WW II NNN  NN DD  DD OO   OO WW   WW SS
    +----+ +----+       WW W WW II NN N NN DD  DD OO   OO WW W WW  SSS
    |####| |####|       WWWWWWW II NN  NNN DD  DD OO   OO WWWWWWW    SS
    |####| |####|       WW   WW II NN   NN DDDDD   OOOO0  WW   WW SSSS
    +----+ +----+       
"

Write-Host "-----------------------------------------------------------------------------------"
Write-Host "              Update Software Packages"
Write-Host "-----------------------------------------------------------------------------------"

$selectedUpdateOption = $UpdateOption
Write-Log "Update Option selected: $($selectedUpdateOption)"
if($selectedUpdateOption -eq "ALL"){
    Write-Log "Updating ALL."

    Write-Host -ForegroundColor Yellow "
 For LOCAL update option! Please ensure you have downloaded the regarding installer files to '$($downloadPath)'.
 "
    Write-Log "Wait for user to continue."
    do{
        $userInput = Read-Host " Do you want to continue (Y/N)"
        Write-Log "User Input: $userInput"
    } while($userInput-ne "Y" -and $userInput -ne "N")

    if($userInput -eq "Y") {

        $SoftwareList = Import-Csv -Path $csvPath -Delimiter ';' | ForEach-Object { New-SoftwareSpec $_ }

        if(-not $GitToken -or -not $ProGetAssetApiKey -or -not $ProGetFeedApiKey){
            Write-Log "Some API Tokens are missing."
        
            #Write-Log "Waiting for GitHub API Token..."
            while([string]::IsNullOrEmpty($GitToken)){
                $GitToken = Read-Host -Prompt " Enter your GitHub API Token"
                #Write-Log "User input for API Token: $GitToken"
            }

            #Write-Log "Waiting for ProGet Asset API Token..."
            while([string]::IsNullOrEmpty($ProGetAssetApiKey)){
                $ProGetAssetApiKey = Read-Host -Prompt " Enter your ProGet Asset API Token"
                #Write-Log "User input for API Token: $GitToken"
            }

            #Write-Log "Waiting for ProGet Feed API Token..."
            while([string]::IsNullOrEmpty($ProGetFeedApiKey)){
                $ProGetFeedApiKey = Read-Host -Prompt " Enter your ProGet Feed API Token"
                #Write-Log "User input for API Token: $GitToken"
            }
        }
        
    }
    elseif($userInput -eq "N"){
        Exit
    }
    
}
elseif($selectedUpdateOption -eq "API"){
    Write-Log "Updating API only."
    Write-Host "-----------------------------------------------------------------------------------"
    Write-Host "              Update Software | Category 'API' only"
    Write-Host "-----------------------------------------------------------------------------------"

    $SoftwareList = Import-Csv -Path $csvPath -Delimiter ';' | 
        where-Object { $_.UpdateOption -eq $selectedUpdateOption } | 
        ForEach-Object { New-SoftwareSpec $_ }

    if(-not $GitToken -or -not $ProGetAssetApiKey -or -not $ProGetFeedApiKey){
        Write-Log "Some API Tokens are missing."
    
        #Write-Log "Waiting for GitHub API Token..."
        while([string]::IsNullOrEmpty($GitToken)){
            $GitToken = Read-Host -Prompt " Enter your GitHub API Token"
            #Write-Log "User input for API Token: $GitToken"
        }

        #Write-Log "Waiting for ProGet Asset API Token..."
        while([string]::IsNullOrEmpty($ProGetAssetApiKey)){
            $ProGetAssetApiKey = Read-Host -Prompt " Enter your ProGet Asset API Token"
            #Write-Log "User input for API Token: $GitToken"
        }

        #Write-Log "Waiting for ProGet Feed API Token..."
        while([string]::IsNullOrEmpty($ProGetFeedApiKey)){
            $ProGetFeedApiKey = Read-Host -Prompt " Enter your ProGet Feed API Token"
            #Write-Log "User input for API Token: $GitToken"
        }
    }
}

elseif($selectedUpdateOption -eq "WEB"){
    Write-Log "Updateing WEB only."
    Write-Host "-----------------------------------------------------------------------------------"
    Write-Host "              Update Software | Category 'WEB' only"
    Write-Host "-----------------------------------------------------------------------------------"

    $SoftwareList = Import-Csv -Path $csvPath -Delimiter ';' | 
        where-Object { $_.UpdateOption -eq $selectedUpdateOption } | 
        ForEach-Object { New-SoftwareSpec $_ }
    

    if(-not $ProGetAssetApiKey -or -not $ProGetFeedApiKey){
        Write-Log "Some API Tokens are missing."

        #Write-Log "Waiting for ProGet Asset API Token..."
        while([string]::IsNullOrEmpty($ProGetAssetApiKey)){
            $ProGetAssetApiKey = Read-Host -Prompt " Enter your ProGet Asset API Token"
            #Write-Log "User input for API Token: $GitToken"
        }

        #Write-Log "Waiting for ProGet Feed API Token..."
        while([string]::IsNullOrEmpty($ProGetFeedApiKey)){
            $ProGetFeedApiKey = Read-Host -Prompt " Enter your ProGet Feed API Token"
            #Write-Log "User input for API Token: $GitToken"
        }
    }
}
elseif($selectedUpdateOption -eq "LOCAL"){
    Write-Log "Updateing LOCAL only."
    Write-Host "-----------------------------------------------------------------------------------"
    Write-Host "              Update Software | Category 'LOCAL' only"
    Write-Host "-----------------------------------------------------------------------------------"

    Write-Host "
 Please ensure you have downloaded the regarding installer files to '$($downloadPath)'."
    Write-Log "Wait for user to continue."
    do{
        $userInput = Read-Host " Do you want to continue (Y/N)"
        Write-Log "User Input: $userInput"
    } while($userInput-ne "Y" -and $userInput -ne "N")
	
    if($userInput -eq "Y") {

        $SoftwareList = Import-Csv -Path $csvPath -Delimiter ';' | 
            where-Object { $_.UpdateOption -eq $selectedUpdateOption } | 
            #where-Object { $_.UpdateOption -eq $selectedUpdateOption -and $_.SourceType -eq 'OfficeCdn' -and $_.SoftwareName -eq "OfficeLTSC2021" -and $_.SubName1 -eq "ProPlus" } | 
            ForEach-Object { New-SoftwareSpec $_ }

        if(-not $ProGetAssetApiKey -or -not $ProGetFeedApiKey){
			Write-Log "Some API Tokens are missing."
		
			#Write-Log "Waiting for ProGet Asset API Token..."
			while([string]::IsNullOrEmpty($ProGetAssetApiKey)){
				$ProGetAssetApiKey = Read-Host -Prompt " Enter your ProGet Asset API Token"
				#Write-Log "User input for API Token: $GitToken"
			}

			#Write-Log "Waiting for ProGet Feed API Token..."
			while([string]::IsNullOrEmpty($ProGetFeedApiKey)){
				$ProGetFeedApiKey = Read-Host -Prompt " Enter your ProGet Feed API Token"
				#Write-Log "User input for API Token: $GitToken"
			}
		}
    }
    elseif($userInput -eq "N"){
        Exit
    }

    
}



Write-Log "Checking for new software versions..."
foreach ($software in $SoftwareList) {
    Write-Log "=== $($software.Publisher) | $($software.SoftwareName) ==="
    $firstLetter = $software.Publisher.Substring(0,1).ToLower()
    $publisher = $software.Publisher
    $Softwarename = $software.SoftwareName
    $ext = $software.PreferredExtension
    $arch = $software.Arch
    $updateOption = $software.UpdateOption

    # Build API URL to list version folders and local storage path for download and checking current version
    Write-Log "Build API URL to list version folders and local storage path for download and checking current versions"

    # 1) Build paths once 
    $paths = Get-SoftwarePaths -Publisher $software.Publisher -SoftwareName $software.SoftwareName -SubName1 $software.SubName1 -SubName2 $software.SubName2 -ManifestSubPath $software.ManifestSubPath -Option $software.UpdateOption
    

    if($updateOption -eq "LOCAL"){
        $apiUrl = "-"
        $rawUrl = "-"
        $localStoragePath = $paths.LocalStoragePath
        $ProGetAssetFolder = $paths.ProGetAssetRelativePath   
    }
    elseif($updateOption -eq "API"){
        $apiUrl = $paths.ApiUrl
        $rawUrl = $paths.RawUrl
        $localStoragePath = $paths.LocalStoragePath
		$ProGetAssetFolder = $paths.ProGetAssetRelativePath
    }
    elseif($updateOption -eq "WEB"){
        $apiUrl = $software.SourceRef 
        $rawUrl = "-"
        $localStoragePath = $paths.LocalStoragePath
        $ProGetAssetFolder = $paths.ProGetAssetRelativePath
    }
    # API Mode as Default
    else{
        $apiUrl = $paths.ApiUrl
        $rawUrl = $paths.RawUrl
        $localStoragePath = $paths.LocalStoragePath
        $ProGetAssetFolder = $paths.ProGetAssetRelativePath
    }    
    

    if([string]::IsNullOrEmpty($($software.SubName1))){
        $subName1 = "-"
    }
    else{
        $subName1 = $software.SubName1
    }
    if([string]::IsNullOrEmpty($($software.SubName2))){
        $subName2 = "-"
    }
    else{
        $subName2 = $software.SubName2
    }
    if([string]::IsNullOrEmpty($($software.ManifestSubPath))){
        $manifestSubPath = "-"
    }
    else{
        $manifestSubPath = $software.ManifestSubPath
    }
    if([string]::IsNullOrEmpty($($software.SourceType))){
        $sourceType = "-"
    }
    else{
        $sourceType = $software.SourceType
    }
    if([string]::IsNullOrEmpty($($software.SourceRef))){
        $sourceRef = "-"
    }
    else{
        $sourceRef = $software.SourceRef
    }
    if([string]::IsNullOrEmpty($($software.AssetPattern))){
        $assetPattern = "-"
    }
    else{
        $assetPattern = $software.AssetPattern
    }

    Write-Log "Sub Name 1:           $subName1"
    Write-Log "Sub Name 2:           $subName2"
    Write-Log "Publisher:            $publisher"
    Write-Log "Installer:            $ext"
    Write-Log "Architecture:         $arch"
    Write-Log "API URL:              $apiUrl"
    Write-Log "Raw Url:              $rawUrl"
    Write-Log "Update Option:        $updateOption"
    Write-Log "SourceType:           $sourceType"
    Write-Log "SourceRef:            $sourceRef"
    Write-Log "Manifest Sub Path:    $manifestSubPath"
    Write-Log "AssetPattern:         $assetPattern"
    Write-Log "ManualRequired:       $($software.ManualVersionRequired)"

    Write-Host "
=== $($software.Publisher) | $($software.SoftwareName) ===
    Sub Name1:            $subName1
    Sub Name2:            $subName2
    Publisher:            $publisher
    Installer:            $ext
    Architecture:         $arch
    API URL:              $apiurl
    RAW URL:              $rawUrl
    Update Option:        $updateOption
    SourceType:           $sourceType
    SourceRef:            $sourceRef
    ManifestSubPath:      $manifestSubPath
    AssetPattern:         $assetPattern
    ManualRequired:       $($software.ManualVersionRequired)"
      

    # 2) Provider -> intent
    $intent = Resolve-LatestReleaseIntent -Software $software -Paths $paths -DownloadPath $downloadPath

<# DEBUG TEST #>
#    $intent | Format-List *
#    Read-Host -Prompt "Continue"
<# DEBUG TEST #>

    if (-not $intent) {
        Write-TrackedWarning "No intent returned for $($software.Publisher) $($software.SoftwareName). Skipping."
        continue
    }

    <# DEBUG #>
    #Write-Host -ForegroundColor Magenta "Intent debug: Version='$($intent.Version)' Url='$($intent.InstallerUrl)'"
    #Write-Log  "INTENT DEBUG: Version='$($intent.Version)' Url='$($intent.InstallerUrl)'"
    <# DEBUG #>

    # 3) Run unified enterprise pipeline
    try {
        Invoke-EnterprisePackageUpdate -Software $software -Paths $paths -Intent $intent -DownloadPath $downloadPath
    }
    catch {
        Write-TrackedError "Pipeline failed for $($software.Publisher) $($software.SoftwareName): $_"
        Write-Log "ERROR: Pipeline failed for $($software.Publisher) $($software.SoftwareName): $_"
        continue
    }
}
Write-Log "=== Finished progress... ==="
$SoftwareList = @($SoftwareList)
$CheckedCount = $SoftwareList.Count
Write-Host "
=== Summary ==="
Write-Host "    Checked $($CheckedCount) software package(s)."
Write-Host -ForegroundColor Yellow "    Total Warnings: $($global:WarningCount)"
Write-Host -ForegroundColor Red "    Total Errors: $($global:ErrorCount)"
if($global:WarningCount -gt 0 -or $global:ErrorCount -gt 0){
    Write-Host -ForegroundColor Cyan "    For more details, look at the logfile:
    '$($logPath)'"
}
Write-Host "    Completed at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

Write-Log "=== Summary ==="
Write-Log "Checked $($SoftwareList.Count) software package(s)."
Write-Log "Total Warnings: $($global:WarningCount)"
Write-Log "Total Errors: $($global:ErrorCount)"
Write-Log "Completed at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

Read-Host " Press 'Enter' key to leave"
