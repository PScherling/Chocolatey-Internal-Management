param(
  [Parameter(Mandatory)]
  [string]$NupkgPath
)

$ErrorActionPreference = 'Stop'

# Require admin
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
  throw "Run PowerShell as Administrator."
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
