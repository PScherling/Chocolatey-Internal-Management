<#
.SYNOPSIS
	Installs the Chocolatey CLI (choco) in an offline-friendly way by downloading the Chocolatey .nupkg,
  	extracting it, and running the embedded installer script.

.DESCRIPTION
	This script automates installation of Chocolatey without using the standard online bootstrapper.
  	It downloads the Chocolatey package (chocolatey.nupkg) either from:
    - the public Chocolatey Community Repository (default), or
    - a user-provided internal URL (e.g., ProGet/Nexus/any HTTP file endpoint)

  	After download, the script:
    1) Extracts the .nupkg as a ZIP to a temporary working directory
    2) Runs tools\chocolateyInstall.ps1 from the package
    3) Ensures the current PowerShell session can access choco.exe via PATH
    4) Prints the installed Chocolatey version

  	Intended for lab / enterprise scenarios where you want reproducible installs and/or restricted internet access.


.PARAMETER DownloadPath
  Local directory to store the downloaded chocolatey.nupkg (e.g. D:\SetupFiles).
  The file will be saved as: <DownloadPath>\chocolatey.nupkg

.PARAMETER UseInternalUrl
  If specified, the script will prompt for a direct internal URL to a Chocolatey .nupkg file
  (e.g. a ProGet asset endpoint). If not specified, the script downloads from the public
  Community Repository.
  

.LINK
    https://community.chocolatey.org/packages/chocolatey
    https://chocolatey.org/install
    https://community.chocolatey.org/courses/installation/installing?method=completely-offline-install
	https://github.com/PScherling
	
.NOTES
          FileName: chocolatey-AutoInstall.ps1
          Solution: Automate Chocolatey Installation
          Author: Patrick Scherling
          Contact: @Patrick Scherling
          Primary: @Patrick Scherling
          Created: 2026-01-19
          Modified: 2026-02-10

          Version - 0.0.1 - (2026-01-29) - Finalized functional version 1.
		  Version - 0.0.2 - (2026-01-30) - Name Change
		  Version - 0.0.3 - (2026-02-10) - Change Parameter "DownloadPath" to "NotMandatory" and set default value


.REQUIREMENTS
  - Run as Administrator
  - PowerShell 5.1+
  - BITS (Start-BitsTransfer) recommended; falls back to Invoke-WebRequest if unavailable/failing


.EXAMPLE
  # Install Chocolatey by downloading from community feed to D:\SetupFiles
  .\chocolatey-AutoInstall.ps1 -DownloadPath "D:\SetupFiles"

    # Install Chocolatey using an internal URL (prompted)
  .\chocolatey-AutoInstall.ps1 -DownloadPath "D:\SetupFiles" -UseInternalUrl
#>

param( 
  [Parameter(Mandatory = $false)] [string] $DownloadPath = "C:\_it\SetupFiles",                                 # e.g. D:\SetupFiles
  [Parameter(Mandatory = $false)] [switch] $UseInternalUrl						 								# e.g. If you enable this switch, you must provide the URL to your internal repo like "http://psc-swrepo1:8624/endpoints/choco-assets/content/Chocolatey/Chocolatey/chocolatey.2.6.0.nupkg"
)

$ErrorActionPreference        = 'Stop'
if($UseInternalUrl){
	$ChocoUrl = Read-Host -Prompt "Enter the Url to the package (e.g. 'http://sw-repo:8624/endpoints/choco-assets/content/Chocolatey/Chocolatey/chocolatey.2.6.0.nupkg')"
}else{
	$ChocoUrl                     = "https://community.chocolatey.org/api/v2/package/chocolatey"
}
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
