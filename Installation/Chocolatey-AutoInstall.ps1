<#
.SYNOPSIS
  Installs the Chocolatey CLI (choco) in an offline-friendly way by downloading a Chocolatey .nupkg,
  extracting it, and running the embedded installer script. Optionally configures an internal NuGet feed
  and imports a self-signed certificate to trust the internal server.

.DESCRIPTION
  This script installs Chocolatey without using the standard online bootstrapper. It downloads the
  Chocolatey package (chocolatey.nupkg) either from:
    - the public Chocolatey Community Repository (default), or
    - a user-provided internal URL (e.g., ProGet/Nexus/HTTP endpoint)

  After download, the script:
    1) Saves chocolatey.nupkg to the specified DownloadPath
    2) Extracts the nupkg as a ZIP into a temporary working folder
    3) Runs tools\chocolateyInstall.ps1 from the extracted package
    4) Ensures the current session can access choco.exe via PATH
    5) Prints the installed Chocolatey version

  Optional behaviors:
    - Adds an internal Chocolatey/NuGet feed as a source and removes the public community source
    - Imports a self-signed certificate from \\<ServerFqdn>\certs into LocalMachine trust stores
      so HTTPS endpoints using that certificate are trusted


.PARAMETER DownloadPath
  Local directory to store the downloaded chocolatey.nupkg.
  Default: C:\_it\SetupFiles

.PARAMETER InternalUrl
  Direct URL to a Chocolatey .nupkg file (e.g., from an internal repository/asset endpoint).
  If not provided, the script uses the Chocolatey Community feed URL.

.PARAMETER InternalSource
  Internal NuGet v2/v3 feed URL to add as a Chocolatey source (e.g., ProGet/Nexus feed endpoint).

.PARAMETER IntSourceName
  Friendly name for the internal Chocolatey source (e.g., "choco-internal").

.PARAMETER Prio
  Priority for the internal source (lower number = higher priority).

.PARAMETER UseSelfSignedCert
  If specified, imports a self-signed certificate from \\<ServerFqdn>\certs into:
    - Cert:\LocalMachine\Root
    - Cert:\LocalMachine\TrustedPeople

.PARAMETER ServerFqdn
  Required when -UseSelfSignedCert is specified. The FQDN of the internal repository server
  hosting the \\<ServerFqdn>\certs share.
  

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
          Modified: 2026-02-11

          Version - 0.0.1 - (2026-01-29) - Finalized functional version 1.
		  Version - 0.0.2 - (2026-01-30) - Name Change
		  Version - 0.0.3 - (2026-02-10) - Change Parameter "DownloadPath" to "NotMandatory" and set default value
          Version - 0.0.4 - (2026-02-11) - Add new parameter(s) for unattended installation


.REQUIREMENTS
  - Run as Administrator
  - PowerShell 5.1+
  - BITS (Start-BitsTransfer) recommended; falls back to Invoke-WebRequest if unavailable/failing


.EXAMPLE
  # Install from community feed and store nupkg in default path
  .\chocolatey-AutoInstall.ps1

  # Install using internal .nupkg URL and configure internal source
  .\chocolatey-AutoInstall.ps1 `
    -InternalUrl "https://repo.local/endpoints/assets/content/Chocolatey/Chocolatey/chocolatey.2.6.0.nupkg" `
    -InternalSource "https://repo.local/nuget/choco-internal/" `
    -IntSourceName "choco-internal" `
    -Prio 1

  # Same as above, but also import self-signed server certificate from \\repo.local\certs
  .\chocolatey-AutoInstall.ps1 `
    -InternalUrl "https://repo.local/.../chocolatey.2.6.0.nupkg" `
    -InternalSource "https://repo.local/nuget/choco-internal/" `
    -IntSourceName "choco-internal" `
    -UseSelfSignedCert `
    -ServerFqdn "repo.local"
#>

param( 
  [Parameter(Mandatory = $false)] [string] $DownloadPath = "C:\_it\SetupFiles",                                 # e.g. D:\SetupFiles
  [Parameter(Mandatory = $false)] [string] $InternalUrl,					 								                              # e.g. your internal repo like "https://psc-swrepo1:8625/endpoints/assets/content/Chocolatey/Chocolatey/chocolatey.2.6.0.nupkg"
  [Parameter(Mandatory = $false)] [string] $InternalSource,                                                     # e.g. your internal nuget source url like "https://psc-swrepo1.local:8625/nuget/choco-feed/"
  [Parameter(Mandatory = $false)] [string] $IntSourceName,                                                      # e.g. Name for the internal nuget feed like "choco-feed"
  [Parameter(Mandatory = $false)] [int] $Prio = 1,                                                              # e.g. Priority for the new source
  [Parameter(Mandatory = $false)] [switch] $UseSelfSignedCert,                                                  # e.g. Use this switch to provide self signed certificate
  [Parameter(Mandatory = $false)] [string] $ServerFqdn                                                          # e.g. Internal Repo Server Fqdn like "PSC-SWREPO1.local"                                 
)

# Enforce: ServerFqdn is required if UseSelfSignedCert is set
if ($UseSelfSignedCert -and [string]::IsNullOrWhiteSpace($ServerFqdn)) {
  throw "Parameter -ServerFqdn is required when using -UseSelfSignedCert."
}

$ErrorActionPreference        = 'Stop'
if($InternalUrl){
	$ChocoUrl = $InternalUrl
}else{
	$ChocoUrl = "https://community.chocolatey.org/api/v2/package/chocolatey"
}
$NupkgPath = "$($DownloadPath)\chocolatey.nupkg"

if (-not (Test-Path $DownloadPath)) {
    New-Item -ItemType Directory -Path $DownloadPath | Out-Null
}

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

Write-Host "=================================================================="
# Import SelfSigned Server Certificate
if($UseSelfSignedCert){
  Write-Host "Importing self signed server certificate"
  $CertShare = "\\$($ServerFqdn)\certs"
  $Cert = Get-ChildItem -Path "$($CertShare)" -Filter *.cer | Where-Object { $_.BaseName -like "*selfsigned*"} | Sort-Object CreationTime -Descending | Select-Object -First 1
  Import-Certificate -FilePath "$($Cert.FullName)" -CertStoreLocation "Cert:\LocalMachine\Root" | Out-Null
  Import-Certificate -FilePath "$($Cert.FullName)" -CertStoreLocation "Cert:\LocalMachine\TrustedPeople" | Out-Null
}

Write-Host "=================================================================="
# Start Download
Write-Host "Start Download"
try{
  Start-DownloadInstallerFile -Url "$ChocoUrl" -DestinationPath "$NupkgPath"
} catch{
  throw "Download could not be started - $_"
}

if (-not (Test-Path $NupkgPath)) {
  throw "File not found: $NupkgPath"
}

Write-Host "=================================================================="
# Set install location (default)
Write-Host "Set install location (default)"
$env:ChocolateyInstall = Join-Path $env:ProgramData 'Chocolatey'
$chocoBin = Join-Path $env:ChocolateyInstall 'bin'

Write-Host "=================================================================="
# Extract nupkg
Write-Host "Extract nupkg"
$work = Join-Path $env:TEMP ("choco-offline-" + ([Guid]::NewGuid().ToString('N')))
New-Item -ItemType Directory -Path $work | Out-Null

$zipPath = Join-Path $work 'chocolatey.zip'
Copy-Item -Path $NupkgPath -Destination $zipPath -Force
Expand-Archive -Path $zipPath -DestinationPath $work -Force

Write-Host "=================================================================="
# Run the embedded installer
Write-Host "Run the embedded installer"
$installPs1 = Join-Path $work 'tools\chocolateyInstall.ps1'
if (-not (Test-Path $installPs1)) {
  throw "Could not find tools\chocolateyInstall.ps1 inside the nupkg."
}

& $installPs1

Write-Host "=================================================================="
# Ensure PATH for this session
Write-Host "Ensure PATH for this session"
if (-not ($env:Path -like "*$chocoBin*")) {
  $env:Path = $env:Path + ";" + $chocoBin
}

Write-Host "Chocolatey installed. Version:" -NoNewline
& (Join-Path $chocoBin 'choco.exe') -v

if ($InternalSource -and $IntSourceName) {
  Write-Host "=================================================================="
  # Configure new internal repository
  Write-Host "Add internal source"
  choco source add -n="$($IntSourceName)" -s="$($InternalSource)" --priority=$($Prio)

  # Disable public repository
  Write-Host "Disable public repository"
  choco source disable -n="chocolatey"
}
else {
  Write-Host "No internal source parameters provided - leaving Chocolatey community source as-is."
}

