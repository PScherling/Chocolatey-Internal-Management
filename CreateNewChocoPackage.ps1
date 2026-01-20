<#
.SYNOPSIS
	
.DESCRIPTION
    
.LINK
	https://github.com/microsoft/winget-pkgs  
    https://docs.chocolatey.org/en-us/guides/
    https://docs.inedo.com/docs/proget/overview
	https://learn.microsoft.com/en-us/windows/package-manager/winget/  
	https://learn.microsoft.com/en-us/powershell/module/powershell-yaml  
	https://github.com/PScherling
    
.NOTES
          FileName: CreateNewChocoPackage.ps1
          Solution: Auto-Create Chocolatey Packages
          Author: Patrick Scherling
          Contact: @Patrick Scherling
          Primary: @Patrick Scherling
          Created: 2026-01-20
          Modified: 2026-01-20

		  Version - 0.0.1 - (2026-01-20) - Finalized functional version 1.
          

          TODO:

.Requirements
    - PowerShell 5.1 or higher (PowerShell 7+ recommended)
	- Chocolatey CLI tool must be installed
		
.Example
http://PSC-SWREPO1:8624/endpoints/choco-assets/content/Microsoft/Edge/Edge_x64_143.0.3650.139.msi
#>
param(
    [Parameter(Mandatory)] [string] $ChocoPackagesPath,     # e.g. "E:\Choco\Packages"
    [Parameter(Mandatory)] [string] $SourceFilePath,        # e.g. "C:\Users\sysadmineuro\Downloads\Chrome.msi"
    [Parameter(Mandatory)] [string] $Publisher,             # e.g. "Microsoft"
    [Parameter(Mandatory)] [string] $SoftwareName,          # e.g. "NotepadPlusPlus"
    [Parameter(Mandatory)] [ValidateSet('x64','x86')] [string] $Arch,                       # e.g. "x64"
    [Parameter(Mandatory)] [string] $Version,               # e.g. "8.8.9"
    [Parameter(Mandatory)] [ValidateSet('exe','msi','msu')] [string]  $FileType,            # e.g. "msi"
    [Parameter(Mandatory)] [ValidateSet('http','https')] [string] $Protocol,                # e.g. "http"
    [Parameter(Mandatory)] [string] $RepoSrv,               # e.g. "PSC-SWREPO1"
    [Parameter(Mandatory)] [string] $AssetName              # e.g. "choco-assets"

)

Clear-Host


$ProGetBaseUrl          = "$($Protocol)://$($RepoSrv):8624"
$ToolsDir               = "$($ChocoPackagesPath)\$($Publisher)\$($SoftwareName)\tools"
$ProGetAssetFolder      = "$($Publisher)/$($SoftwareName)"
$FileName               = "$($SoftwareName)_$($Arch)_$($Version).$($FileType)"
$FileSHA256             = ""

#$ProGetURI = "$($Protocol)://$($RepoSrv):8624/endpoints/$($AssetName)/content/$($Publisher)/$($FileName)"

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
        [Parameter(Mandatory)] [ValidateSet('exe','msi','msu')] [string] $FileType,
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
    $updated = 1
    try{
        Set-Content -Path $scriptPath -Value $content -Encoding UTF8
    }
    catch{
        $updated = 0
    }

    return $updated
}


# Create base directory
try{
    New-Item -ItemType Directory -Path "$($ChocoPackagesPath)\$($Publisher)" -Force | Out-Null
}
catch{
    throw "Directory '$($ChocoPackagesPath)\$($Publisher)' could not be created - $_"
}

try{
    Set-Location "$($ChocoPackagesPath)\$($Publisher)"
}
catch{
    throw "Could not change location to '$($ChocoPackagesPath)\$($Publisher)' - $_"
}

# Create package template
try{
    choco new "$($SoftwareName)" --version="$($Version)" | Out-Null
}
catch{
    throw "Could not create chocolatey package template for '$($SoftwareName)' - $_"
}

# Backup 'chocolateyinstall.ps1' script
try{
    Copy-Item -Path "$($ToolsDir)\chocolateyinstall.ps1" -Destination "$($ToolsDir)\chocolateyinstall.ps1.orig" -Force | out-null
}
catch{
    throw "Could not backup 'chocolateyinstall.ps1' script - $_"
}

# Get Sha256 Value from SourceFile
try{
    $FileSHA256 = Get-FileHash "$($SourceFilePath)" -Algorithm SHA256 | Select-Object Hash
}
catch{
    throw "Could not get SHA256 Hash from source file '$($SourceFilePath)' - $_"
}

# Rename soruce file
try{
    Rename-Item -Path "$($SourceFilePath)" -NewName "$($FileName)" | Out-Null
}
catch{
    throw "Could not rename file '$($SourceFilePath)' to '$($SoftwareName)_$($Arch)_$($Version).$($FileType)'"
}


try{
    $updScript = Update-ChocoInstallationScript -ToolsDir "$($ToolsDir)" -ProGetBaseUrl "$($ProGetBaseUrl)" -ProGetAssetDir "$($AssetName)" -AssetFolderPath "$($ProGetAssetFolder)" -InstallerFileName "$($FileName)" -FileType "$($FileType)" -Arch "$($Arch)" -Sha "$($FileSHA256.Hash)"
}
catch{
    throw "Could not update 'chocolateyinstall.ps1' script - $_"
}

