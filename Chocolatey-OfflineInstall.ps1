<#
.SYNOPSIS


.DESCRIPTION


.LINK
    https://community.chocolatey.org/packages/chocolatey
    https://chocolatey.org/install
    https://community.chocolatey.org/courses/installation/installing?method=completely-offline-install
	https://github.com/PScherling
	
.NOTES
          FileName: chocolatey-OfflineInstall.ps1
          Solution: 
          Author: Patrick Scherling
          Contact: @Patrick Scherling
          Primary: @Patrick Scherling
          Created: 2026-01-19
          Modified: 2026-01-29

          Version - 0.0.1 - (2026-01-29) - Finalized functional version 1.



.EXAMPLE

    Requires administrative privileges.
#>

param( 
  [Parameter(Mandatory)][string]$DownloadPath                                  # e.g. D:\SetupFiles
)

$ErrorActionPreference        = 'Stop'
$ChocoUrl                     = "https://community.chocolatey.org/api/v2/package/chocolatey"
$NupkgPath                    = "$($DownloadPath)\chocolatey.nupkg"

# Downloading File
function Start-DownloadInstallerFile {
    param (
        [string]$Url,
        [string]$DestinationPath
    )

    try {
        Start-BitsTransfer -Source $Url -Destination $DestinationPath -ErrorAction Stop
        Write-Host "Downloaded successfully using BITS: $DestinationPath"
    } catch {
        #Write-Warning "BITS download failed. Trying fallback method."
        Write-Host -ForegroundColor Yellow "WARNING: BITS download failed. Trying fallback method - $_"

        # Fallback: Use Invoke-WebRequest
        try {
            Write-Host "URL: $Url"
            Invoke-WebRequest -Uri $Url -OutFile $DestinationPath
            Write-Host "Downloaded successfully with fallback method."
        } catch {
            
            throw "ERROR: Fallback download failed - $_"

            continue
        }
    }


}

# Require admin
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
  throw "Run PowerShell as Administrator."
}

# Start Download
try{
  Start-DownloadInstallerFile -Url "$ChocoUrl" -DestinationPath "$NupkgPath"
} catch{
  throw "Download could not be started - $_"
}

if (-not (Test-Path $NupkgPath)) {
  throw "File not found: $NupkgPath"
}

# Set install location (default)
$env:ChocolateyInstall = Join-Path $env:ProgramData 'Chocolatey'
$chocoBin = Join-Path $env:ChocolateyInstall 'bin'

# Extract nupkg
$work = Join-Path $env:TEMP ("choco-offline-" + ([Guid]::NewGuid().ToString('N')))
New-Item -ItemType Directory -Path $work | Out-Null

$zipPath = Join-Path $work 'chocolatey.zip'
Copy-Item -Path $NupkgPath -Destination $zipPath -Force
Expand-Archive -Path $zipPath -DestinationPath $work -Force

# Run the embedded installer
$installPs1 = Join-Path $work 'tools\chocolateyInstall.ps1'
if (-not (Test-Path $installPs1)) {
  throw "Could not find tools\chocolateyInstall.ps1 inside the nupkg."
}

& $installPs1

# Ensure PATH for this session
if (-not ($env:Path -like "*$chocoBin*")) {
  $env:Path = $env:Path + ";" + $chocoBin
}

Write-Host "Chocolatey installed. Version:" -NoNewline
& (Join-Path $chocoBin 'choco.exe') -v
