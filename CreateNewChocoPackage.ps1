<#
.SYNOPSIS
	Creates a new internal Chocolatey package template, updates the install script to point to a ProGet Asset URL
    (including SHA256), builds the .nupkg and pushes it to a ProGet Chocolatey/NuGet feed.

.DESCRIPTION
    CreateNewChocoPackage.ps1 automates the initial creation of internal Chocolatey packages in an on-prem environment.
    It is designed for a ProGet and Chocolatey workflow where installer binaries (MSI/EXE/MSU/APPX) are hosted in a ProGet
    Asset Directory and Chocolatey packages reference those internal URLs.

    The script performs the following steps:
      1) Creates a vendor base directory under the package root (Publisher)
      2) Generates a Chocolatey package template (choco new) for the specified SoftwareName and Version
      3) Creates a backup of tools\chocolateyinstall.ps1
      4) Calculates SHA256 of the provided installer file (source)
      5) Renames the installer file to a standardized naming convention:
         [SoftwareName]_[Arch]_[Version].[FileType]
      6) Updates tools\chocolateyinstall.ps1:
         - Sets $url / $url64 to the ProGet Asset content URL
         - Updates fileType, checksum/checksum64 and checksumType* to SHA256
      7) Prompts the user to review and adjust:
         - silentArgs
         - .nuspec metadata (title, authors, description, etc.)
      8) Builds the package (.nupkg) using choco pack
      9) Pushes the package to the configured ProGet feed using choco push

    Notes / Intended Use:
      - This script currently updates the Chocolatey install script to reference the ProGet asset URL. Uploading the
      installer into the ProGet Asset Directory is assumed to be handled separately (manual or via another script).
      - Designed for internal repositories (on-prem). No public Chocolatey community feed publishing is intended.
      - Requires an API key for the ProGet Chocolatey/NuGet feed (not the Asset Directory).

.PARAMETER ChocoPackagesPath
    Root folder where your Chocolatey package sources are stored.
    Example: E:\Choco\Packages

.PARAMETER SourceFilePath
    Full path to the installer file that should be packaged (EXE/MSI/MSU).
    Example: C:\Users\...\Downloads\WinSCP.exe

.PARAMETER Publisher
    Vendor / Publisher name used for folder structure.
    Example: Microsoft, WinSCP, NotepadPlusPlus

.PARAMETER SoftwareName
    Chocolatey package name (and folder name) used for the package template.
    Example: WinSCP, NotepadPlusPlus

.PARAMETER Arch
    Target architecture. Valid values: x64, x86. Default: x86

.PARAMETER Version
    Software version string used for package versioning and filename convention.
    Example: 8.8.9

.PARAMETER Protocol
    Protocol used to build ProGet URLs. Valid values: http, https. Default: http

.PARAMETER ProGetSrv
    ProGet server hostname (or FQDN).
    Example: PSC-SWREPO1

.PARAMETER ProGetPort
    ProGet web port. Default: 8624

.PARAMETER AssetName
    Name of the ProGet Asset Directory where installer files are hosted.
    Example: choco-assets

.PARAMETER FeedName
    Name of the ProGet Chocolatey/NuGet feed for pushing .nupkg packages.
    Example: internal-choco

.PARAMETER ProGetFeedKey
    ProGet API key with permission to publish packages to the specified feed (NOT the assets directory).

.LINK
	https://github.com/microsoft/winget-pkgs  
    https://docs.chocolatey.org/en-us/guides/
    https://docs.inedo.com/docs/proget/overview
    https://learn.microsoft.com/en-us/windows/package-manager/winget/
    https://github.com/microsoft/winget-pkgs
	https://github.com/PScherling
    
.NOTES
          FileName: CreateNewChocoPackage.ps1
          Solution: Auto-Create Chocolatey Packages
          Author: Patrick Scherling
          Contact: @Patrick Scherling
          Primary: @Patrick Scherling
          Created: 2026-01-20
          Modified: 2026-01-21

		  Version - 0.0.1 - (2026-01-21) - Finalized functional version 1.
          

          TODO:

.Requirements
    - PowerShell 5.1 or higher (PowerShell 7+ recommended)
	- Chocolatey CLI tool must be installed
		
.EXAMPLE
    # Create a new package for WinSCP (x86 EXE), update chocolateyinstall.ps1, build and push to ProGet feed
    .\CreateNewChocoPackage.ps1 `
        -ChocoPackagesPath "E:\Choco\Packages" `
        -SourceFilePath "C:\Users\Admin\Downloads\WinSCP.exe" `
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
        -ProGetFeedKey "xxxxxxxxxxxxxxxxxxxx"

.EXAMPLE
    # Create an x86 MSI package and push to ProGet (defaults: Arch=x86, Protocol=http, Port=8624)
    .\CreateNewChocoPackage.ps1 `
        -ChocoPackagesPath "E:\Choco\Packages" `
        -SourceFilePath "C:\Temp\MyApp.msi" `
        -Publisher "VendorX" `
        -SoftwareName "MyApp" `
        -Version "1.2.3" `
        -FileType "msi" `
        -ProGetSrv "PSC-SWREPO1" `
        -AssetName "choco-assets" `
        -FeedName "internal-choco" `
        -ProGetFeedKey "xxxxxxxxxxxxxxxxxxxx"

#>
param(
    [Parameter(Mandatory)] [string] $ChocoPackagesPath,                                     # e.g. "E:\Choco\Packages"
    [Parameter(Mandatory)] [string] $SourceFilePath,                                        # e.g. "C:\Users\sysadmineuro\Downloads\WinSCP.exe"
    [Parameter(Mandatory)] [string] $Publisher,                                             # e.g. "Microsoft"
    [Parameter(Mandatory)] [string] $SoftwareName,                                          # e.g. "NotepadPlusPlus"
    [Parameter(Mandatory = $false)] [ValidateSet('x64','x86')] [string] $Arch = "x86",      # e.g. "x64" | Default = "x86"
    [Parameter(Mandatory)] [string] $Version,                                               # e.g. "8.8.9"
    [Parameter(Mandatory)] [ValidateSet('exe','msi','msu','appx')] [string]  $FileType,            		# e.g. "msi"
    [Parameter(Mandatory = $false)] [ValidateSet('http','https')] [string] $Protocol = "http",       	# e.g. Default = "http"
    [Parameter(Mandatory)] [string] $ProGetSrv,                                             # e.g. "PSC-SWREPO1"
    [Parameter(Mandatory = $false)] [string] $ProGetPort = "8624",                          # e.g. Default = "8624"
    [Parameter(Mandatory)] [string] $AssetName,                                             # e.g. "choco-assets"
    [Parameter(Mandatory)] [string] $FeedName,                                              # e.g. "choco-internal"
    [Parameter(Mandatory)] [string] $ProGetFeedKey                                          # e.g. [Your-ProGet-Feed-API-Key] (Not to the Assets!)

)

Clear-Host


$ProGetBaseUrl                  = "$($Protocol)://$($ProGetSrv):$($ProGetPort)"
$ToolsDir                       = "$($ChocoPackagesPath)\$($Publisher)\$($SoftwareName)\tools"
$ProGetAssetFolder              = "$($Publisher)/$($SoftwareName)"
$FileName                       = "$($SoftwareName)_$($Arch)_$($Version).$($FileType)"
$userInput                      = ""
$ProGetAssetURI                 = "$($ProGetBaseUrl)/endpoints/$($AssetName)/content/$($ProGetAssetFolder)/$($FileName)"
$ProGetFeedURI                  = "$($ProGetBaseUrl)/nuget/$($FeedName)/"

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
        [Parameter(Mandatory)] [ValidateSet('exe','msi','msu','appx')] [string] $FileType,
        [Parameter(Mandatory)] [ValidateSet('x64','x86')] [string] $Arch,
        [Parameter(Mandatory)] [string] $Sha                        
    )
    $returnCode = 0
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

    #Write-Log "ToolsDir: $ToolsDir | FileName: $InstallerFileName | Hash: $Sha | AssetUrl: $assetUrl"


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

    try{
        Set-Content -Path $scriptPath -Value $content -Encoding UTF8
    }
    catch{
        throw "Could not update 'chocolateyinstall.ps1' script - $_"
        $returnCode = 1
    }

    return $returnCode
}


# Create base directory
function New-BaseDirectory {
    param(
        [Parameter(Mandatory)] [string] $Path,              # e.g. "E:\Choco\Packages"
        [Parameter(Mandatory)] [string] $Manufacturer       # e.g. Microsoft
    )
    $returnCode = 0
    try{
        New-Item -ItemType Directory -Path "$($Path)\$($Manufacturer)" -Force | Out-Null
    }
    catch{
        throw "Directory '$($Path)\$($Manufacturer)' could not be created - $_"
        $returnCode = 1
    }

    try{
        Set-Location "$($Path)\$($Manufacturer)"
    }
    catch{
        throw "Could not change location to '$($Path)\$($Manufacturer)' - $_"
        $returnCode = 1
    }
    return $returnCode
}

# Create package template
function New-ChocoPackage {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Ver
    )
    $returnCode = 0
    try{
        choco new "$($Name)" --version="$($Ver)" | Out-Null
    }
    catch{
        throw "Could not create chocolatey package template for '$($Name)' - $_"
        $returnCode = 1
    }
    return $returnCode
}

# Backup 'chocolateyinstall.ps1' script
function Set-InstallScript {
    param(
        [Parameter(Mandatory)] [string] $Path       # e.g. "E:\Choco\Packages\WinSCP\WinSCP\tools\chocolateyinstall.ps1"
    )
    $returnCode = 0
    try{
        Copy-Item -Path "$($Path)" -Destination "$($Path).orig" -Force | out-null
    }
    catch{
        throw "Could not backup '$($Path)' file - $_"
        $returnCode = 1
    }
    return $returnCode
}

# Get Sha256 Value from SourceFile
function Get-HashValue {
    param(
        [Parameter(Mandatory)] [string] $Path       # e.g. "C:\Users\sysadmineuro\Downloads\WinSCP_x86_6.5.5.exe"
    )
    $returnCode = 0
    try{
        $FileHash = Get-FileHash "$($Path)" -Algorithm SHA256 | Select-Object Hash
    }
    catch{
        throw "Could not get SHA256 Hash from source file '$($Path)' - $_"
        $returnCode = 1
    }
    return [pscustomobject]@{
        FileSHA256      = $FileHash.Hash
        ReturnCode      = $returnCode
    }
}

# Rename soruce file
function Rename-SoftwareFile {
    param(
        [Parameter(Mandatory)] [string] $Path,      # e.g. "C:\Users\sysadmineuro\Downloads\WinSCP_x86_6.5.5.exe"
        [Parameter(Mandatory)] [string] $NewFileName   # e.g. WinSCP_x86_6.6.exe
    )
    $returnCode = 0
    try{
        Rename-Item -Path "$($Path)" -NewName "$($NewFileName)" | Out-Null
    }
    catch{
        throw "Could not rename file '$($Path)' to '$($NewFileName)'"
        $returnCode = 1
    }
    return [pscustomobject]@{
        FileName        = $NewFileName
        ReturnCode      = $returnCode
    }
}

function Start-Packaging {
    param(
        [Parameter(Mandatory)] [string] $NuSpecPath,        # e.g. "E:\Choco\Packages\WinSCP\WinSCP\winscp.nuspec"
        [Parameter(Mandatory)] [string] $OutDir             # e.g. "E:\Choco\Packages\WinSCP\WinSCP"
    )
    $returnCode = 0
    try{
        choco pack "$($NuSpecPath)" --outdir "$($OutDir)" | Out-Null
    }
    catch{
        throw "Could not create chocolatey package '.nupkg' - $_"
        $returnCode = 1
    }
    $Package = Get-ChildItem -Path "$($OutDir)\*" -Include "*.nupkg" | select-object FullName
    return [pscustomobject]@{
        NuPkg           = $Package.FullName
        ReturnCode      = $returnCode
    }
}

function Start-PushPackage {
    param(
        [Parameter(Mandatory)] [string] $PkgPath,        # e.g. "E:\Choco\Packages\WinSCP\WinSCP\winscp.1.0.0.nupkg"
        [Parameter(Mandatory)] [string] $Source,         # e.g. "http://PROGET01:8624/nuget/internal-choco"
        [Parameter(Mandatory)] [string] $Key             # e.g. [Your-API-Key] for the ProGet Feed (not asset!)
    )
    $returnCode = 0
    try{
        choco push "$($PkgPath)" --source="$($Source)" --api-key="$($Key)" --force | Out-Null
    }
    catch{
        throw "Could not push '$($PkgPath)' to '$($Source)' - $_"
        $returnCode = 1
    }
    return $returnCode
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
Write-Host "              Create New Software Package For Choclatey"
Write-Host "-----------------------------------------------------------------------------------"
Write-Host "=== $($Publisher) | $($SoftwareName) ===
    Base directory:            $($ChocoPackagesPath)\$($Publisher)
    Source File:               $($SourceFilePath)
    Version:                   $($Version)
    Architecture:              $($Arch)
    File Type:                 $($FileType)
    ProGet Asset Location:     $($ProGetAssetURI)
    ProGet Feed Location:      $($ProGetFeedURI)
"

Write-Host "Starting with creation..."
Write-Host "Create new base directory"
$dir            = New-BaseDirectory -Path "$($ChocoPackagesPath)" -Manufacturer "$($Publisher)"
if($dir -eq 0){
    Write-Host -ForegroundColor Green "Base directory created for $($Publisher)"
}
elseif($dir -eq 1){
    Write-Host -ForegroundColor Red "Base directory not created"
}

Write-Host "Create new package"
$pkg            = New-ChocoPackage -Name "$($SoftwareName)" -Ver "$($Version)"
if($pkg -eq 0){
    Write-Host -ForegroundColor Green "New software package created for $($SoftwareName)"
}
elseif($pkg -eq 1){
    Write-Host -ForegroundColor Red "Software package not created"
}

Write-Host "Backup installation script"
$setScript      = Set-InstallScript -Path "$($ToolsDir)\chocolateyinstall.ps1"
if($setScript -eq 0){
    Write-Host -ForegroundColor Green "Backup of installation script created"
}
elseif($setScript -eq 1){
    Write-Host -ForegroundColor Red "Backup of installation script not created"
}

Write-Host "Fetch hash value from installation file"
$shaValue       = Get-HashValue -Path "$($SourceFilePath)"
if($($shaValue.ReturnCode) -eq 0){
    Write-Host -ForegroundColor Green "Hash value from installation file fetched: $($shaValue.FileSHA256)"
}
elseif($($shaValue.ReturnCode) -eq 1){
    Write-Host -ForegroundColor Red "Hash value from installation file not fetched"
}

Write-Host "Rename installation file to new naming convention"
$rnmFile        = Rename-SoftwareFile -Path "$($SourceFilePath)" -NewFileName "$($FileName)"
if($($rnmFile.ReturnCode) -eq 0){
    Write-Host -ForegroundColor Green "Installation file renamed to $($rnmFile.FileName)"
}
elseif($($rnmFile.ReturnCode) -eq 1){
    Write-Host -ForegroundColor Red "Installation file not renamed"
}

Write-Host "Update content of installation script"
$updScript      = Update-ChocoInstallationScript -ToolsDir "$($ToolsDir)" -ProGetBaseUrl "$($ProGetBaseUrl)" -ProGetAssetDir "$($AssetName)" -AssetFolderPath "$($ProGetAssetFolder)" -InstallerFileName "$($FileName)" -FileType "$($FileType)" -Arch "$($Arch)" -Sha "$($shaValue.FileSHA256)"
if($updScript -eq 0){
    Write-Host -ForegroundColor Green "Installation script updated"
}
elseif($updScript -eq 1){
    Write-Host -ForegroundColor Red "Installation script not updated"
}


Write-Host -ForegroundColor Yellow "
Dont't forget to check and update the silent installation arguments inside 'chocolateyinstall.ps1'!
Dont't forget to check and update the '.nuspec' file and provide more information about the software!"

Write-Host "
Only continue if you have checked the mentioned files above."
do{
    $userInput = Read-Host " Do you want to continue (Y/N)"
} while($userInput-ne "Y" -and $userInput -ne "N")

if($userInput -eq "Y") {
    Write-Host "Attempt to build package from '$($ChocoPackagesPath)\$($Publisher)\$($SoftwareName)\$($SoftwareName).nuspec'"
    $build      = Start-Packaging -NuSpecPath "$($ChocoPackagesPath)\$($Publisher)\$($SoftwareName)\$($SoftwareName).nuspec" -OutDir "$($ChocoPackagesPath)\$($Publisher)\$($SoftwareName)"
    if($($build.ReturnCode) -eq 0){
        Write-Host -ForegroundColor Green "Package '$($build.NuPkg)' successfully created"
    }
    elseif($($build.ReturnCode) -eq 1){
        Write-Host -ForegroundColor Red "Package '.nupkg' for $($SoftwareName) not created"
    }
    
    Write-Host "Attempting to push '$($build.NuPkg)' to '$($ProGetFeedURI)'"
    $push       = Start-PushPackage -PkgPath "$($build.NuPkg)" -Source "$($ProGetFeedURI)" -Key "$($ProGetFeedKey)"
    if($push -eq 0){
        Write-Host -ForegroundColor Green "Package '$($build.NuPkg)' successfully pushed"
    }
    elseif($push -eq 1){
        Write-Host -ForegroundColor Red "Package '$($build.NuPkg)' not pushed"
    }
}
elseif($userInput -eq "N"){
    Exit
}

Write-Host "=== Progress finished ==="
