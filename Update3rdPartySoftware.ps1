<#
.SYNOPSIS
	Automates downloading, updating, and synchronizing third-party software installers from multiple sources (Winget API, direct web links, or local downloads).
.DESCRIPTION
    The **Update3rdPartySoftware.ps1** script is an advanced automation tool designed to maintain up-to-date third-party software repositories 
	for enterprise deployment environments (e.g., MDT, WDS, or SCCM).  
	It dynamically checks for new software versions, downloads the latest installers, and synchronizes them across local and deployment share directories.
	
	It supports three main update modes:
	- **API Mode:** Uses the official Microsoft WinGet GitHub repository to query and fetch installers via the GitHub API.
	- **WEB Mode:** Downloads installers directly from vendor websites using static links defined in a CSV file.
	- **LOCAL Mode:** Imports pre-downloaded installers from a designated local directory for manual updates or offline maintenance.
	
	The script reads from a structured CSV file (`SoftwareList.csv`) defining each software package’s publisher, name, architecture, update method, and file preferences.  
	It automatically detects changes, replaces old installers, logs all actions, and provides error and warning summaries.
	
	Features:
	- Modular structure with dynamic mode selection (API / WEB / LOCAL / ALL)
	- Integration with GitHub API for WinGet manifest parsing and version checks
	- YAML parsing via `powershell-yaml` module (automatically installed if missing)
	- Automatic handling of nested installers and fallback download mechanisms
	- Logging of all progress, warnings, and errors to `.\Logs\Update3rdPartySoftware`
	- Interactive and color-coded PowerShell console interface
	- File synchronization to both local storage and WDS deployment shares
	
	This script is particularly useful for:
	- Deployment administrators managing large software libraries
	- Automated update maintenance of application repositories
	- Enterprise software packaging and version management
.LINK
	https://github.com/microsoft/winget-pkgs  
	https://learn.microsoft.com/en-us/windows/package-manager/winget/  
	https://learn.microsoft.com/en-us/powershell/module/powershell-yaml  
	https://github.com/PScherling
    
.NOTES
          FileName: Update3rdPartySoftware.ps1
          Solution: Auto-Update 3rd Party Software on MDT/WDS Server
          Author: Patrick Scherling
          Contact: @Patrick Scherling
          Primary: @Patrick Scherling
          Created: 2025-07-16
          Modified: 2026-01-22

          Version - 0.0.1 - () - Finalized functional version 1.
          Version - 0.0.2 - () - Adapting Software Directory Structure.
          Version - 0.0.3 - () - Finalized functional version.
          Version - 0.0.4 - () - Working on LOCAL Option.
          Version - 0.0.5 - () - Working on WEB Option.
          Version - 0.0.6 - () - Bug fixing.
          Version - 0.0.7 - () - Bug fixing.
          Version - 0.0.8 - () - Update parse yaml logic for "nestedInstallers"
          Version - 0.0.9 - () - Cleanup of obsolete code
		  Version - 0.0.10 - (2026-01-22) - Adapting for ProGet and Chocolatey Envoronment
          

          TODO:

.Requirements
	- PowerShell 5.1 or higher (PowerShell 7+ recommended)
	- GitHub Personal Access Token for API access
	- Module: `powershell-yaml` (auto-installed if missing)
	- Internet access for API and web modes
	- Access to local and WDS share paths
		
.Example
	PS> .\Update3rdPartySoftware.ps1
	Starts the script interactively, allowing you to choose between API, WEB, LOCAL, or ALL update modes.

	PS> .\Update3rdPartySoftware.ps1
	 Choose an Option (1-5): 4
	Runs the full update process for all configured software in the CSV file using every available update source.

	PS> powershell.exe -ExecutionPolicy Bypass -File "C:\Scripts\Update3rdPartySoftware.ps1"
	Schedules or runs the script unattended for automated nightly software updates.
#>

Clear-Host

###
### Config
###
$global:WarningCount 			= 0
$global:ErrorCount 				= 0
$filetimestamp 					= Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$logPath 						= Join-Path -Path "E:\UpdateScripts\Logs\Update3rdPartySoftware" -ChildPath "Update3rdPartySoftware_$($filetimestamp).log"
$myToken 						= ""
$userInput 					    = ""
$baseApiUrl 					= "https://api.github.com/repos/microsoft/winget-pkgs/contents/manifests"
$baseRawUrl 					= "https://raw.githubusercontent.com/microsoft/winget-pkgs/master/manifests"
#$updateOption 					= "API" # Defualt is API | Options: API or LOCAL
$selectedUpdateOption 			= "ALL" # Defualt is ALL | Options: ALL, API, WEB or LOCAL
$csvPath 						= Join-Path -Path "E:\UpdateScripts" -ChildPath "SofwareList.csv"
#$localStorageBasePath 			= "S:\Sources\Software"
#$wdsShareBasePath 				= "D:\DeploymentShare\Applications"
$downloadPath 					= "E:\UpdateScripts\temp\Downloads"
if (-not (Test-Path $downloadPath)) {
    Write-Log "Download Directory not found. Creating '$($downloadPath)'"
    try{
        New-Item -ItemType Directory -Path $downloadPath | Out-Null
    } catch{
        #Write-Error "Download directory could not be created. $_"
        Write-TrackedError "Download directory could not be created. $_"
        Write-Log "ERROR: Download directory could not be created. $_"
    }
}

# Mapping known InstallerType values to extensions
$installerTypeToExtension = @{
    exe     = "exe"
    msi     = "msi"
    msix    = "msix"
    nullsoft = "exe"
    inno    = "exe"
    wix     = "msi"
    burn    = "exe"
    zip     = "zip"
    appx    = "appx"
}
<#
$SoftwareList = Import-Csv -Path $csvPath -Delimiter ';' | ForEach-Object {
    [pscustomobject]@{
        Publisher           = $_.Publisher
        SoftwareName        = $_.SoftwareName
        SubName1            = $_.SubName1
        SubName2            = $_.SubName2
        PreferredExtension  = $_.PreferredExtension
        Arch                = $_.Arch
        UpdateOption        = $_.UpdateOption
        WebLink             = $_.WebLink
    }
}
#>

# ProGet Environment
$ProGetBaseUrl 					= "http://PSC-SWREPO1:8624"
$ProGetAssetDir       			= "choco-assets"
$ProGetAssetApiKey    			= ""   # API key with View/Download (+ Add/Repackage if you upload)
$ProGetFeedApiKey    			= ""   # API key with View/Download (+ Add/Repackage if you upload)
$ProGetChocoFeedName  			= "internal-choco"
$ProGetChocoPushUrl   			= "$ProGetBaseUrl/nuget/$ProGetChocoFeedName"  # works with choco push
# Where your Chocolatey package *source folders* live (nuspec + tools\ scripts)
$ChocoPackageSourceRoot 		= "E:\Choco\Packages"
$newAssetFileSHA256             = ""




# Logging function
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

# Define Software Paths
function Get-SoftwarePaths {
    param (
        [string]$Publisher,
        [string]$SoftwareName,
        [string]$SubName1,
        [string]$SubName2
    )

    $firstLetter = $Publisher.Substring(0,1).ToLower()
    $publisherForAssets = Convert-NameForProGetPath $Publisher
    $softwareForAssets  = Convert-NameForProGetPath $SoftwareName

    if ([string]::IsNullOrEmpty($SubName1) -and [string]::IsNullOrEmpty($SubName2)) {
        $subFolder1 = ""
        $subFolder2 = ""

        $paths = @{
            FirstLetter        = $firstLetter
            ApiUrl             = "$($baseApiUrl)/$($firstLetter)/$($Publisher)/$($SoftwareName)"
            RawUrl             = "$($baseRawUrl)/$($firstLetter)/$($Publisher)/$($SoftwareName)"
            #LocalStoragePath   = "$($localStorageBasePath)\$($Publisher)\$($SoftwareName)"
            #WdsPath            = "$($wdsShareBasePath)\$($Publisher) $($SoftwareName)"
			#ProGetAssetPath    = "$($ProGetBaseUrl)/endpoints/$($ProGetAssetDir)/content/$($publisherForAssets)/$($softwareForAssets)"
            ProGetAssetRelativePath = "$($publisherForAssets)/$($softwareForAssets)" # e.g. NotepadPlusPlus/NotepadPlusPlus
        }
    } 
    elseif(-not [string]::IsNullOrEmpty($SubName1) -and [string]::IsNullOrEmpty($SubName2)){
        $subFolder1 = "$($SubName1)"
        $subFolder2 = ""

        $paths = @{
            FirstLetter        = $firstLetter
            ApiUrl             = "$($baseApiUrl)/$($firstLetter)/$($Publisher)/$($SoftwareName)/$($subFolder1)"
            RawUrl             = "$($baseRawUrl)/$($firstLetter)/$($Publisher)/$($SoftwareName)/$($subFolder1)"
            #LocalStoragePath   = "$($localStorageBasePath)\$($Publisher)\$($SoftwareName)\$($subFolder1)"
            #WdsPath            = "$($wdsShareBasePath)\$($Publisher) $($SoftwareName) $($subFolder1)"
            ProGetAssetRelativePath = "$($publisherForAssets)/$($softwareForAssets)/$($subFolder1)" 
        }
    }
    elseif(-not [string]::IsNullOrEmpty($SubName1) -and -not [string]::IsNullOrEmpty($SubName2)){
        $subFolder1 = "$($SubName1)"
        $subFolder2 = "$($SubName2)"

        $paths = @{
            FirstLetter        = $firstLetter
            ApiUrl             = "$($baseApiUrl)/$($firstLetter)/$($Publisher)/$($SoftwareName)/$($subFolder1)/$($subFolder2)"
            RawUrl             = "$($baseRawUrl)/$($firstLetter)/$($Publisher)/$($SoftwareName)/$($subFolder1)/$($subFolder2)"
            #LocalStoragePath   = "$($localStorageBasePath)\$($Publisher)\$($SoftwareName)\$($subFolder1)\$($subFolder2)"
            #WdsPath            = "$($wdsShareBasePath)\$($Publisher) $($SoftwareName) $($subFolder1) $($subFolder2)"
            ProGetAssetRelativePath = "$($publisherForAssets)/$($softwareForAssets)/$($subFolder1)/$($subFolder2)" 
        }
    }

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
            Write-Host "URL: $Url"
            Invoke-WebRequest -Uri $Url -OutFile $DestinationPath
            Write-Log "Fallback download completed: $DestinationPath"
            Write-Host "    Downloaded successfully with fallback method."
        } catch {
            #Write-Warning "Fallback download failed - $_"
            Write-TrackedError "Fallback download failed - $_"
            Write-Log "ERROR: Fallback download failed - $_"
            $download = 0
            continue
        }
    }

    return $download
}

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
    
    <#if (-not $filename -or [string]::IsNullOrWhiteSpace($filename) -or $filename.StartsWith('?')) {
        Write-TrackedWarning "Web filename for $SoftwareName is invalid ('$filename'), applying fallback."
        Write-Log "WARNING: Web filename for $SoftwareName is invalid ('$filename'), applying fallback."
        $filename = "$($SoftwareFileName -replace '\s','').win-x64.$FormattedVersion$PreferredExtension"
    }#>

    return $filename
}

function Get-WebFilename {
    param (
        [string]$url,
        [string]$extension
    )
    

    <#
    try {
        $response = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -ErrorAction Stop
        if ($response.Headers.'Content-Disposition') {
            
            if ($response.Headers.'Content-Disposition' -match 'filename="?([^";]+)"?') {
                return $nameMatches[1]
            }
        }
        # If no content-disposition header, fallback to URL basename (if any)
        return [System.IO.Path]::GetFileName($url)
    }#>
    try {
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
        
        # Find the first file link, or filter by extension if needed
        $fileLink = $response.Links | Where-Object { $_.href -match "$($extension)" } | Select-Object -First 1

        if ($fileLink) {
            Write-Host "    Downloadable file found at $url"
            Write-Log "Downloadable file found at $url"
            return [System.IO.Path]::GetFileName($fileLink.href)
        }
        else{
            Write-TrackedError "No downloadable file found at $url"
            Write-Log "ERROR: No downloadable file found at $url"
            return $null
        }
    }
    catch {
        Write-TrackedWarning "Failed to get remote filename from $url : $_"
        Write-Log "WARNING: Failed to get remote filename from $url : $_"
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
    Write-Host "    Copy new version to '$($Dest)'"
    try{
        Copy-Item -Path "$($Source)" -Destination "$($Dest)" -Force
        Write-Log "Copied new version to '$($Dest)'"
    } catch {
        Write-Log "ERROR: Failed to copy '$($Dest)' - $_"
        #Write-Error "Failed to copy '$($dest)' - $_"
        Write-TrackedError "Failed to copy '$($Dest)' - $_"
    }
}

function Publish-ProGetAssetFile {
    param(
        [Parameter(Mandatory)] [string] $LocalFilePath,     # e.g. E:\UpdateScripts\temp\Downloads\NotepadPlusPlus_x64_8.9.exe
        [Parameter(Mandatory)] [string] $AssetFolder,       # e.g. NotepadPlusPlus/NotepadPlusPlus
        [Parameter(Mandatory)] [string] $AssetFileName,     # e.g. NotepadPlusPlus_x64_8.9.exe
        [Parameter(Mandatory)] [string] $Key,
        [ValidateSet('POST','PUT','PATCH')] [string] $Method = 'POST'
    )

    $uri = "$ProGetBaseUrl/endpoints/$ProGetAssetDir/content/$AssetFolder/$AssetFileName"

    $headers = @{
        "X-ApiKey"     = "$Key"
        "Content-Type" = "application/octet-stream"
    }

    $bytes = [System.IO.File]::ReadAllBytes($LocalFilePath)

    Write-Log "Start upload to: $uri"
    Write-Host "    Start upload to: $uri"
    $publish = 1
    try{
        Invoke-RestMethod -Uri $uri -Method $Method -Headers $headers -Body $bytes -ErrorAction Stop | Out-Null
    }
    catch{
        $publish = 0
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

    # ProGet can return either an array OR { items: [...] }
    #if ($null -ne $AssetItems.items) { return $AssetItems.items }

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
                    Name    = $name
                    Version = [Version]$verStr
                    Parent  = $item.parent
                    Size    = $item.size
                }
            }
            #Debug
            #Write-Host "DEBUG: name='$name' version='$verStr' parent='$item.parent' size='$item.size'"
        }
        
    }

    if (-not $hits) { return $null }

    # 3) Select latest version
    $latest = $hits | Sort-Object Version -Descending | Select-Object -First 1

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
        Name       = $latest.Name
        Version    = $latest.Version.ToString()
        AssetPath  = "$($AssetFolderPath)/$($latest.Name)"
        MetadataUrl= "$ProGetBaseUrl/endpoints/$ProGetAssetDir/metadata/$AssetFolderPath/$($latest.Name)"
        ContentUrl = "$ProGetBaseUrl/endpoints/$ProGetAssetDir/content/$AssetFolderPath/$($latest.Name)"
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
        [Parameter(Mandatory)] [ValidateSet('exe','msi','msu','appx','msix','appxbundle','msixbundle')] [string] $FileType,
        [Parameter(Mandatory)] [ValidateSet('x64','x86')] [string] $Arch,
        [Parameter(Mandatory)] [string] $Sha                        
    )

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
    else {
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
        $updated = 0
    }

    return $updated
}

function Convert-NameForProGetPath {
    param(
        [Parameter(Mandatory)] [string] $Name
    )
    return ($Name -replace '\+', 'Plus')
}


###
### Start
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
            Write-Host "PowerShell Module 'powershell-yaml' imported."
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
            Write-Host "PowerShell Module 'powershell-yaml' installed and imported."
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
Write-Host "              Update 3rd-Party Software"
Write-Host "-----------------------------------------------------------------------------------"
Write-Host "
    Update Otpions
    1) Update API only software
    2) Update Local only software
    3) Update Web only software
    4) Update All
    5) Leave
"
do {
    $choice = Read-Host " Choose an Option (1-5)"
    Write-Log "User Input: $choice"
    switch ($choice) {
        1 { $selectedUpdateOption = "API" }
        2 { $selectedUpdateOption = "LOCAL" }
        3 { $selectedUpdateOption = "WEB" }
        4 { $selectedUpdateOption = "ALL" }
        5 { Exit }
        default { 
            Write-Log " Wrong Input."
            Write-Host "Wrong Input. Please choose an option above." 
        }
    }
    Write-Log "User choice: $($selectedUpdateOption)"
} while ($choice -notin '1','2','3','4','5')

if($selectedUpdateOption -eq "ALL"){
    Write-Log "Updateing ALL."

    Write-Host "
 For LOCAL update option! Please ensure you have downloaded the regarding installer files to '$($downloadPath)'."
    Write-Log "Wait for user to continue."
    do{
        $userInput = Read-Host " Do you want to continue (Y/N)"
        Write-Log "User Input: $userInput"
    } while($userInput-ne "Y" -and $userInput -ne "N")

    if($userInput -eq "Y") {
        
		
        $SoftwareList = Import-Csv -Path $csvPath -Delimiter ';' | ForEach-Object {
            [pscustomobject]@{
                Publisher           = $_.Publisher
                SoftwareName        = $_.SoftwareName
                SubName1            = $_.SubName1
                SubName2            = $_.SubName2
                PreferredExtension  = $_.PreferredExtension
                Arch                = $_.Arch
                UpdateOption        = $_.UpdateOption
                WebLink             = $_.WebLink
            }
        }

        Write-Log "Waiting for GitHub API Token..."
        while([string]::IsNullOrEmpty($myToken)){
            $myToken = Read-Host -Prompt " Enter your GitHub API Token"
            #Write-Log "User input for API Token: $myToken"
        }

        Write-Log "Waiting for ProGet Asset API Token..."
        while([string]::IsNullOrEmpty($ProGetAssetApiKey)){
            $ProGetAssetApiKey = Read-Host -Prompt " Enter your ProGet Asset API Token"
            #Write-Log "User input for API Token: $myToken"
        }

        Write-Log "Waiting for ProGet Feed API Token..."
        while([string]::IsNullOrEmpty($ProGetFeedApiKey)){
            $ProGetFeedApiKey = Read-Host -Prompt " Enter your ProGet Feed API Token"
            #Write-Log "User input for API Token: $myToken"
        }
    }
    elseif($userInput -eq "N"){
        Exit
    }
    
}
elseif($selectedUpdateOption -eq "API"){
    Write-Log "Updateing API only."
    Write-Host "-----------------------------------------------------------------------------------"
    Write-Host "              Update API only Software"
    Write-Host "-----------------------------------------------------------------------------------"

    $SoftwareList = Import-Csv -Path $csvPath -Delimiter ';' |
    where-Object { $_.UpdateOption -eq $selectedUpdateOption } | 
    ForEach-Object {
        [pscustomobject]@{
            Publisher           = $_.Publisher
            SoftwareName        = $_.SoftwareName
            SubName1            = $_.SubName1
            SubName2            = $_.SubName2
            PreferredExtension  = $_.PreferredExtension
            Arch                = $_.Arch
            UpdateOption        = $_.UpdateOption
            WebLink             = $_.WebLink
        }
    }

    Write-Log "Waiting for API Token..."
    while([string]::IsNullOrEmpty($myToken)){
        $myToken = Read-Host -Prompt " Enter your GitHub API Token"
        #Write-Log "User input for API Token: $myToken"
    }

    Write-Log "Waiting for ProGet Asset API Token..."
    while([string]::IsNullOrEmpty($ProGetAssetApiKey)){
        $ProGetAssetApiKey = Read-Host -Prompt " Enter your ProGet Asset API Token"
        #Write-Log "User input for API Token: $myToken"
    }

    Write-Log "Waiting for ProGet Feed API Token..."
    while([string]::IsNullOrEmpty($ProGetFeedApiKey)){
        $ProGetFeedApiKey = Read-Host -Prompt " Enter your ProGet Feed API Token"
        #Write-Log "User input for API Token: $myToken"
    }
}
<#
elseif($selectedUpdateOption -eq "WEB"){
    Write-Log "Updateing WEB only."
    Write-Host "-----------------------------------------------------------------------------------"
    Write-Host "              Update WEB only Software"
    Write-Host "-----------------------------------------------------------------------------------"

    $SoftwareList = Import-Csv -Path $csvPath -Delimiter ';' |
    where-Object { $_.UpdateOption -eq $selectedUpdateOption } | 
    ForEach-Object {
        [pscustomobject]@{
            Publisher           = $_.Publisher
            SoftwareName        = $_.SoftwareName
            SubName1            = $_.SubName1
            SubName2            = $_.SubName2
            PreferredExtension  = $_.PreferredExtension
            Arch                = $_.Arch
            UpdateOption        = $_.UpdateOption
            WebLink             = $_.WebLink
        }
    }

    Write-Log "Waiting for ProGet Asset API Token..."
    while([string]::IsNullOrEmpty($ProGetAssetApiKey)){
        $ProGetAssetApiKey = Read-Host -Prompt " Enter your ProGet Asset API Token"
        #Write-Log "User input for API Token: $myToken"
    }

    Write-Log "Waiting for ProGet Feed API Token..."
    while([string]::IsNullOrEmpty($ProGetFeedApiKey)){
        $ProGetFeedApiKey = Read-Host -Prompt " Enter your ProGet Feed API Token"
        #Write-Log "User input for API Token: $myToken"
    }
}
elseif($selectedUpdateOption -eq "LOCAL"){
    Write-Log "Updateing LOCAL only."
    Write-Host "-----------------------------------------------------------------------------------"
    Write-Host "              Update LOCAL only Software"
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
        ForEach-Object {
            [pscustomobject]@{
                Publisher           = $_.Publisher
                SoftwareName        = $_.SoftwareName
                SubName1            = $_.SubName1
                SubName2            = $_.SubName2
                PreferredExtension  = $_.PreferredExtension
                Arch                = $_.Arch
                UpdateOption        = $_.UpdateOption
                WebLink             = $_.WebLink
            }
        }

        Write-Log "Waiting for ProGet Asset API Token..."
        while([string]::IsNullOrEmpty($ProGetAssetApiKey)){
            $ProGetAssetApiKey = Read-Host -Prompt " Enter your ProGet Asset API Token"
            #Write-Log "User input for API Token: $myToken"
        }

        Write-Log "Waiting for ProGet Feed API Token..."
        while([string]::IsNullOrEmpty($ProGetFeedApiKey)){
            $ProGetFeedApiKey = Read-Host -Prompt " Enter your ProGet Feed API Token"
            #Write-Log "User input for API Token: $myToken"
        }
    }
    elseif($userInput -eq "N"){
        Exit
    }

    
}
#>


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

    if($updateOption -eq "LOCAL"){
        $paths = Get-SoftwarePaths -Publisher $publisher -SoftwareName $Softwarename -SubName1 $software.SubName1 -SubName2 $software.SubName2

        $apiUrl = "-"
        $rawUrl = "-"
        #$localStoragePath = $paths.LocalStoragePath
        #$wdsPath = $paths.WdsPath
        $ProGetAssetFolder = $paths.ProGetAssetRelativePath   
    }
    elseif($updateOption -eq "API"){
        $paths = Get-SoftwarePaths -Publisher $publisher -SoftwareName $Softwarename -SubName1 $software.SubName1 -SubName2 $software.SubName2
        $apiUrl = $paths.ApiUrl
        $rawUrl = $paths.RawUrl
        #$localStoragePath = $paths.LocalStoragePath
        #$wdsPath = $paths.WdsPath
		$ProGetAssetFolder = $paths.ProGetAssetRelativePath
    }
    elseif($updateOption -eq "WEB"){
        $paths = Get-SoftwarePaths -Publisher $publisher -SoftwareName $Softwarename -SubName1 $software.SubName1 -SubName2 $software.SubName2

        $apiUrl = $software.WebLink
        $rawUrl = "-"
        #$localStoragePath = $paths.LocalStoragePath
        #$wdsPath = $paths.WdsPath
        $ProGetAssetFolder = $paths.ProGetAssetRelativePath
    }
    # API Mode as Default
    else{
        $paths = Get-SoftwarePaths -Publisher $publisher -SoftwareName $Softwarename -SubName1 $software.SubName1 -SubName2 $software.SubName2
        $apiUrl = $paths.ApiUrl
        $rawUrl = $paths.RawUrl
        #$localStoragePath = $paths.LocalStoragePath
        #$wdsPath = $paths.WdsPath
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

    Write-Log "Sub Name 1:           $subName1"
    Write-Log "Sub Name 2:           $subName2"
    Write-Log "Publisher:            $publisher"
    Write-Log "Installer:            $ext"
    Write-Log "Architecture:         $arch"
    Write-Log "API URL:              $apiUrl"
    Write-Log "Raw Url:              $rawUrl"
    Write-Log "Update Option:        $updateOption"

    Write-Host "
=== $($software.Publisher) | $($software.SoftwareName) ===
    Sub Name1:            $subName1
    Sub Name2:            $subName2
    Publisher:            $publisher
    Installer:            $ext
    Architecture:         $arch
    API URL:              $apiurl
    RAW URL:              $rawUrl
    Update Option:        $updateOption"

    if($updateOption -eq "API"){
        # Create headers for authentication
        $headers = @{
            "User-Agent" = "PowerShell"
            "Authorization" = "token $myToken"
        }
        Write-Log "Create headers for authentication."
        
        # Call GitHub API to get directory contents
        Write-Log "Call GitHub API to get directory contents"
        $versionsJson = Invoke-RestMethod -Uri $apiUrl -Headers $headers

        # Filter only directories (versions)
        Write-Log "Filter only directories (versions)"
        $versionDirs = $versionsJson | Where-Object { $_.type -eq "dir" } | Select-Object -ExpandProperty name

        # Filter and parse only valid semantic versions
        $parsedVersionObjects = foreach ($dir in $versionDirs) {
            if ($dir -match '^\d+(\.\d+){1,3}$') {
                [PSCustomObject]@{
                    Original = $dir
                    Parsed = [Version]$dir
                }
            }
        }

        if (-not $parsedVersionObjects) {
            #Write-Warning "No valid semantic versions found for $Softwarename"
            Write-TrackedWarning "No valid semantic versions found for $Softwarename"
            Write-Log "WARNING: No valid semantic versions found for $Softwarename"
            continue
        }

        # Sort descending and get latest
        $latestVersionObj = $parsedVersionObjects | Sort-Object Parsed -Descending | Select-Object -First 1
        $latestVersion = $latestVersionObj.Original

        Write-Host "    Latest version is:    $latestVersion"
        Write-Log "Latest version is: $latestVersion"

        # List files in latest version folder
        Write-Log "List files in latest version folder"
        $versionApiUrl = "$($apiUrl)/$($latestVersion)"
        $filesJson = Invoke-RestMethod -Uri $versionApiUrl -Headers $headers #@{ "User-Agent" = "PowerShell" }

        # Find yaml manifest file (ends with .yaml)
        Write-Log "Find yaml manifest file (ends with .yaml)"
        $yamlFile = $filesJson | Where-Object { $_.name -like "*.installer.yaml" } | Select-Object -First 1 -ExpandProperty name

        if (-not $yamlFile) {
            #Write-Warning "No YAML manifest found for $Softwarename version $latestVersion"
            Write-TrackedWarning "No YAML manifest found for $Softwarename version $latestVersion"
            Write-Log "WARNING: No YAML manifest found for $Softwarename version $latestVersion"
            continue
        }

        # Build raw url to YAML
        #$rawYamlUrl = "https://raw.githubusercontent.com/microsoft/winget-pkgs/master/manifests/$firstLetter/$publisher/$Softwarename/$latestVersion/$yamlFile"
        $rawYamlUrl = "$rawUrl/$latestVersion/$yamlFile"
        Write-Host "    Reading YAML from $rawYamlUrl"
        Write-Log "Reading YAML from $rawYamlUrl"

        $yamlContent = Invoke-RestMethod -Uri $rawYamlUrl -Headers $headers #@{ "User-Agent" = "PowerShell" }

        # Parse YAML - Requires PowerShell 7+
        Write-Log "Parse YAML"
        $yamlParsed = $yamlContent | ConvertFrom-Yaml

        # Find installer matching Arch and PreferredExtension
        Write-Log "Find installer matching Arch and PreferredExtension"

        $preferredExt = $software.PreferredExtension.TrimStart('.')  # e.g., "exe", "msi", "msix"
        
        
        # If InstallerType is missing in installer, use top-level one
        $installers = $yamlParsed.Installers | ForEach-Object {
            if (-not $_.InstallerType -and $yamlParsed.InstallerType) {
                $_ | Add-Member -MemberType NoteProperty -Name InstallerType -Value $yamlParsed.InstallerType -Force
            }
            $_
        }
        
        <#
        # If primary InstallerType and nested InstallerType is missing in installer, use top-level one
        $installers = $yamlParsed.Installers | ForEach-Object {
            if (
                (-not $_.InstallerType) -and
                (-not $_.NestedInstallerType) -and
                $yamlParsed.InstallerType -and
                $yamlParsed.NestedInstallerType
            ) {
                $_ | Add-Member -MemberType NoteProperty -Name InstallerType -Value $yamlParsed.InstallerType -Force
                $_ | Add-Member -MemberType NoteProperty -Name NestedInstallerType -Value $yamlParsed.NestedInstallerType -Force
            }
            $_
        }
        #>

        # Match logic with better fallback
        $installer = $installers | Where-Object {
            $_.Architecture -eq $software.Arch -and (
                ($installerTypeToExtension[$_.InstallerType] -eq $preferredExt) -or
                ($_.InstallerUrl -like "*.$preferredExt*")
            )
        } | Select-Object -First 1

        if (-not $installer) {
            Write-TrackedWarning "No matching installer found for $Softwarename with Arch $($software.Arch) and extension $($software.PreferredExtension)"
            Write-Log "WARNING: No matching installer found for $Softwarename with Arch $($software.Arch) and extension $($software.PreferredExtension)"
        } 
        else {
            Write-Log "Matched installer: $($installer.InstallerUrl)"
            $installerUrl = $installer.InstallerUrl
            $Softwarename = Convert-NameForProGetPath $SoftwareName
            $publisher = Convert-NameForProGetPath $publisher

            Write-Host "    Installer URL for $Softwarename ($($software.Arch)): $($installerUrl)"
            Write-Log "Installer URL for $Softwarename ($($software.Arch)): $($installerUrl)"

            # Construct final file name: SWName_SubName1_Arch_Version.Extension
            Write-Log "Construct final file name: Name_Arch_Version.Extension"
            $ext = [IO.Path]::GetExtension($installerUrl.Split("?")[0]) # fallback if not from YAML
            if (-not $ext -or $ext -eq '') {
                $ext = $software.PreferredExtension
            }

            if($subName1 -ne "-"){
                $Softwarename = "$($Softwarename)_$($subName1)"
            }
            if($subName2 -ne "-"){
                $Softwarename = "$($Softwarename)_$($subName2)"
            }


            
            $finalFileName = "$($Softwarename)_$($software.Arch)_$($latestVersion)$($ext)"
            Write-Log "Final filename: $finalFileName"
            
            # Get existing installer version
            # Escape software name for use in regex
            $escapedSoftwareName = [regex]::Escape($Softwarename)

            # Excape software subname for use in regex
            #$escapedSWSubName1 = [regex]::Escape($subName1)
            #$escapedSWSubName2 = [regex]::Escape($subName2)
            
            # Upload to ProGet Assets
            Write-Log "=== Start Checking Software Task ==="
            Write-Log "Get existing installer version for $Softwarename | $escapedSoftwareName"
			Write-Log "Looking for installer in '$($ProGetAssetFolder)'"
            Write-Host "  === Start Checking Software Task ==="
			Write-Host "    Get existing installer version for $Softwarename"
			Write-Host "    Looking for installer in '$($ProGetAssetFolder)'"
            
			try{
				$existingInstaller = Get-ExistingInstallerFromProGetAssets `
					-AssetFolderPath $ProGetAssetFolder `
					-SoftwareName $Softwarename `
					-Arch $software.Arch `
					-Extension $ext
			}
			catch{
				Write-TrackedError "Could not get local installer in '$($ProGetAssetFolder)' - $_"
                Write-Log "ERROR: Could not get local installer in '$($ProGetAssetFolder)' - $_"
			}
			
			if ($null -eq $existingInstaller) {
				Write-TrackedWarning "No existing installer found in ProGet Assets for $Softwarename ($($software.Arch)$ext)"
				Write-Log "WARNING: No existing installer found in ProGet Assets for $Softwarename ($($software.Arch)$ext)"
			}
			else{
				Write-Log "Current version: $($existingInstaller.Name)"
				Write-Log "Available version: $($finalFileName)"
				Write-Host "    Current version:      $($existingInstaller.Name)"
				Write-Host "    Available version:    $($finalFileName)"
			}

            if($($existingInstaller.Name) -eq $finalFileName){
                Write-Log "Version for $Softwarename already up to date. Skipping download."
                Write-Host -ForegroundColor Green "    Version for $Softwarename already up to date. Skipping download."
                $shouldDownload = $false
            }
            else{
                Write-Log "New version for $Softwarename available."
                Write-Host -ForegroundColor Green "    New version for $Softwarename available."
                $shouldDownload = $true
            }

            if($shouldDownload) {
                $newFile = Join-Path $downloadPath $finalFileName
                $currentLocalFile = "$($ChocoPackageSourceRoot)\$($Softwarename)\tools\$($existingInstaller.Name)"
                #$currentWDSFile = "$($wdsPath)\$($existingInstaller.Name)"
                #$newLocalFile = "$($localStoragePath)\$($finalFileName)"
                #$newWDSFile = "$($wdsPath)\$($finalFileName)"
				#$currentAssetFile = "$($existingInstaller.Name)"
				#$newAssetFile = "$($finalFileName)"

                
                #Debug output
                #Write-Host "    Current Asset File: $currentAssetFile"
                #Write-Host "    New Asset File: $newAssetFile"

                Write-Log "=== Start File Download Task ==="
                Write-Log "Downloading to $newFile"
                Write-Host "  === Start File Download Task ==="
                Write-Host "    Downloading to: '$($newFile)'"

                # Start Download
                try{
                    $dwnFile = Start-DownloadInstallerFile -Url "$installerUrl" -DestinationPath "$newFile"
                } catch{
                    Write-Log "WARNING: Download could not be started - $_"
                    Write-TrackedError "Download could not be started - $_"
                }

                # Clean old installer file in Chocolatey Package Directory
                Write-Log "Removing old installer file"
                Write-Host "    Removing old installer file"
                if(Test-Path -path "$($currentLocalFile)"){
                    
                    Remove-File -Path "$($currentLocalFile)"
                }
                else{
                    Write-TrackedWarning "File '$($currentLocalFile)' not found - $_"
                    Write-Log "WARNING: File '$($currentLocalFile)' not found - $_"
                }
                

                # Copy File into Chocolatey Package Directory
                Write-Log "Copy new installer file into choclatey package directory"
                Write-Host "    Copy new installer file into choclatey package directory"
                try{
                    Copy-File -Source "$($newFile)" -Dest "$($ChocoPackageSourceRoot)\$($Softwarename)\tools"
                }
                catch{
                    Write-TrackedWarning "Directory '$($ChocoPackageSourceRoot)\$($Softwarename)\tools' not found - $_"
                    Write-Log "WARNING: Directory '$($ChocoPackageSourceRoot)\$($Softwarename)\tools' not found - $_"
                }
				
                Write-Log "=== Start File Upload Task ==="
                Write-Log "Uploading to ProGet Assets"
                Write-Host "  === Start File Upload Task ==="
                Write-Host "    Uploading to ProGet Assets"
				try{
					$pubAssetFile = Publish-ProGetAssetFile -LocalFilePath "$($newFile)" -AssetFolder "$($ProGetAssetFolder)" -AssetFileName "$($finalFileName)" -Key "$ProGetAssetApiKey" -Method POST
				}
				catch{
                    Write-Log "ERROR: Upload not successfull - $_"
                    Write-TrackedError "Upload not successfull - $_"
				}
				
				# Fetch SHA256 from metadata
                Write-Log "=== Start Chocolatey Package Task ==="
                Write-Log "Fetching SH256 hash from new file"
                Write-Host "  === Start Chocolatey Package Task ==="
                Write-Host "    Fetching SH256 hash from new file"
                try{
                    $newAssetFileSHA256 = Get-ProGetAssetSha256 -FolderPath "$($ProGetAssetFolder)" -FileName "$($finalFileName)" -Key "$ProGetAssetApiKey"
                }
                catch{
                    Write-Log "ERROR: Could not fetch SHA256 information from new file - $_"
                    Write-TrackedError "Could not fetch SHA256 information from new file - $_"
                }

				# Update Chocolatey package
                Write-Log "Update Chocolatey package"
                Write-Host "    Update Chocolatey package"
				# You should store each package source in a stable folder: E:\ChocoSrc\<PackageId>\
                $packageId = "$($Softwarename)" 
                $pkgDir    = Join-Path $ChocoPackageSourceRoot $packageId
                $nuspec    = Join-Path $pkgDir "$packageId.nuspec"
                $checksums = Join-Path $pkgDir "tools\checksums.json"
                
                Write-Log "Package Information: ID='$($packageId)' DIR='$($pkgDir)' Nuspec='$($nuspec)' Checksum='$($checksums)' PushURL='$($ProGetChocoPushUrl)'"
                Write-Host "    PackageID:            $packageId"
                Write-Host "    Package Directory:    $pkgDir"
                Write-Host "    Nuspec File:          $nuspec"
                Write-Host "    Checksum File:        $checksums"
                Write-Host "    Push URL:             $ProGetChocoPushUrl"

                if (-not (Test-Path $pkgDir)) { 
                    Write-Log "ERROR: Chocolatey package source folder not found: $pkgDir - $_"
                    Write-TrackedError "Chocolatey package source folder not found: $pkgDir - $_" 
                }
                if (-not (Test-Path $nuspec)) { 
                    Write-Log "ERROR: Nuspec not found: $nuspec - $_"
                    Write-TrackedError "Nuspec not found: $nuspec - $_" 
                }
                if (-not (Test-Path $checksums)) { 
                    Write-Log "WARNING: checksums.json not found: $checksums - Creating it..."
                    Write-TrackedWarning "checksums.json not found: $checksums - Creating it..." 
                    try{
                        New-Item -ItemType File -Path "$checksums" | Out-Null

                        @"
{
  "x64": "",
  "x86": ""
}
"@ | Set-Content -Path $checksums -Encoding UTF8

                    }
                    catch{
                        Write-Log "ERROR: Checksum file could not be created - $_"
                        Write-TrackedError "Checksum file could not be created - $_" 
                    }
                }

                Write-Log "Set '$nuspec' to new Version to: $latestVersion"
                Write-Host "    Set '$nuspec' to new Version to: $latestVersion"
                try{
                    $updNuspec = Set-NuspecVersion  -NuspecPath "$nuspec" -NewVersion "$latestVersion"
                }
                catch{
                    Write-Log "ERROR: Could not set chocolatey nuspec version - $_"
                    Write-TrackedError "Could not set chocolatey nuspec version - $_"
                }

                Write-Log "Set checksum file: $checksums"
                Write-Host "    Set checksum file: $checksums"
                try{
                    Set-ChecksumsJson  -ChecksumsPath "$checksums" -Arch "$($software.Arch)" -Sha "$newAssetFileSHA256"
                }
                catch{
                    Write-Log "ERROR: Could not set checksum file - $_"
                    Write-TrackedError "Could not set checksum file - $_"
                }

                # Adapt Chocolatey Install PowerShell Script "tools\chocolateyinstall.ps1"
                Write-Log "Update Installation script"
                Write-Host "    Update Installation script"

                $extNoDot = $ext.TrimStart('.').ToLower()
                
                try{
                    $updScript = Update-ChocoInstallationScript -ToolsDir "$($pkgDir)\tools" -ProGetBaseUrl "$($ProGetBaseUrl)" -ProGetAssetDir "$($ProGetAssetDir)" -AssetFolderPath "$($ProGetAssetFolder)" -InstallerFileName "$($finalFileName)" -FileType "$extNoDot" -Arch "$($software.Arch)" -Sha "$newAssetFileSHA256"
                }
                catch{
                    Write-Log "ERROR: Could not update installation script - $_"
                    Write-TrackedError "Could not update installation script - $_"
                }

				# Pack and Push the Chocolatey package to ProGet feed
                Write-Log "Pack and Push the Chocolatey package to ProGet feed"
                Write-Host "    Pack and Push the Chocolatey package to ProGet feed"
                try{
				    $nupkgPath = Publish-ChocoPackageToProGet -PackageSourceDir $pkgDir -PushUrl $ProGetChocoPushUrl -Key $ProGetFeedApiKey
                }
                catch{
                    Write-Log "ERROR: Could not pack and push new chocolatey package - $_"
                    Write-TrackedError "Could not pack push new chocolatey package - $_"
                }

                # Clean temp download directory
                if($nupkgPath){ 
                    Remove-File -Path "$($newFile)" 
                }
                else{
                    Write-Log "WARNING: Removing of temp downloaded file '$($newFile)' not executed."
                    Write-TrackedWarning "Removing of temp downloaded file '$($newFile)' not executed."
                }

                Write-Host "  === Task Summary ==="
                Write-Log "=== Task Summary ==="
                if($dwnFile -eq 1){
                    Write-Host -ForegroundColor Green "    New Software downloaded successfully"
                    Write-Log "New Software downloaded successfully"
                }
                else{
                    Write-Host -ForegroundColor Red "    New Software download failed"
                    Write-Log "New Software download failed"
                }
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

        } 
    }
    else{
        Write-Log "WARNING: No download option available."
        Write-TrackedWarning "No download option available."
    }
}
Write-Log "=== Finished progress... ==="

Write-Host "
=== Summary ==="
Write-Host "    Checked $($SoftwareList.Count) software package(s)."
Write-Host -ForegroundColor Yellow "    Total Warnings: $($global:WarningCount)"
Write-Host -ForegroundColor Red "    Total Errors: $($global:ErrorCount)"
if($global:WarningCount -gt 0 -or $global:ErrorCount -gt 0){
    Write-Host "    For more details, look at the logfile:
    '$($logPath)'"
}
Write-Host "    Completed at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

Write-Log "=== Summary ==="
Write-Log "Checked $($SoftwareList.Count) software package(s)."
Write-Log "Total Warnings: $($global:WarningCount)"
Write-Log "Total Errors: $($global:ErrorCount)"
Write-Log "Completed at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

Read-Host " Press any key to leave"
