<#
.SYNOPSIS
    Installs a Chocolatey package silently during an MDT deployment task sequence.
    
.DESCRIPTION
    This script installs a specified Chocolatey application in an unattended MDT
    deployment workflow. Chocolatey CLI must already be installed (e.g., via MDT
    application dependency).

    The script:
        - Installs the specified Chocolatey package
        - Creates a structured local log file
        - Optionally uploads the log file to a deployment server share
        - Optionally deletes the local log file after completion

    Designed for enterprise deployment scenarios using Microsoft Deployment Toolkit (MDT).

.PARAMETER AppName
  Name of the Chocolatey package to install (e.g. "chocolateygui").

.PARAMETER UploadLog
  If specified, uploads the generated log file to a central deployment server.

.PARAMETER SrvIP
  Required when -UploadLog is used.
  Specifies the deployment server IP or hostname hosting the log share.

.PARAMETER DeleteLogfile
  If specified, deletes the local log file after execution.
    
.LINK
    https://chocolatey.org
    https://docs.chocolatey.org/en-us/choco/commands/
    https://docs.chocolatey.org/en-us/choco/commands/install/
    https://docs.chocolatey.org/en-us/chocolatey-gui/setup/installation/#package-parameters
    https://learn.microsoft.com/en-us/mem/configmgr/mdt/
    https://github.com/PScherling
    
.NOTES
          FileName: Install_ChocoApplication.ps1
          Solution: Application Deployment for MDT via Chocolatey
          Author: Patrick Scherling
          Contact: @Patrick Scherling
          Primary: @Patrick Scherling
          Created: 2025-02-12
          Modified: 2025-02-12

          Version - 0.1.0 - () - Finalized functional version 1.

          TODO:

.REQUIREMENTS
  - Must run with administrative privileges
  - Chocolatey CLI must be installed prior to execution
  - MDT Task Sequence (State Restore phase recommended)
		
.EXAMPLE
  # Install Chocolatey GUI
  .\Install_ChocoApplication.ps1 -AppName "chocolateygui"

  # Install 7zip and upload log
  .\Install_ChocoApplication.ps1 -AppName "7zip" -UploadLog -SrvIP "192.168.1.10"
#>
param( 
  [Parameter(Mandatory = $true)] [string] $AppName,                                 # e.g. ChocolateyGUI  
  [Parameter(Mandatory = $false)] [switch] $UploadLog,                              # e.g. Use this switch to enable logging for MDT
  [Parameter(Mandatory = $false)] [string] $SrvIP,                                  # e.g. 192.168.1.1        
  [Parameter(Mandatory = $false)] [switch] $DeleteLogfile,                          # e.g. Use this switch to delete the local logfile            
)

# Enforce: Parameter AppName
if ([string]::IsNullOrWhiteSpace($AppName)) {
  throw "Parameter -AppName is required."
  exit 1
}

# Enforce: SrvIP is required if UploadLog is set
if ($UploadLog -and [string]::IsNullOrWhiteSpace($SrvIP)) {
  throw "Parameter -SrvIP is required when using -UploadLog."
  exit 1
}


# Log file path and function to log messages
$CompName                           = $env:COMPUTERNAME
$DateTime                           = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$logFileName                        = "Install_$($AppName)_$($CompName)_$($DateTime).log"
$localLogFilePath                   = "C:\_it"
$localLogFile                       = "$($localLogFilePath)\$($logFileName)"

$choco                              = Join-Path $env:ProgramData "chocolatey\bin\choco.exe"

if($UploadLog){
    $logFilePath                    = "\\$($SrvIP)\Logs$\Custom\Software"
    $logFile                        = "$($logFilePath)\$($logFileName)"
}


function Write-Log {
    param ([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp $Message" | Out-File -FilePath $localLogFile -Append
}
Write-Log "Start Logging."


<#
# Create required directories
#>
Write-Log "Create required directories."
$directories = @(
	"$($localLogFilePath)"
)
foreach ($dir in $directories) {
	If (-not (Test-Path $dir)) { 
		Write-Log "Creating Directory '$($dir)'."
		try{
			New-Item -Path $dir -ItemType Directory
		}
		catch{
			Write-Log "ERROR: Directory '$($dir)' could not be created."
		}
	}
    else{
        Write-Log "Directory '$($dir)' already exists."
    }
}

<#
# Application Install
#>
Write-Log "Installing Application '$($AppName)'."
try{
    if (Test-Path $choco) {
        #start-process -WindowStyle minimized -FilePath "$($choco)" -ArgumentList "install $($AppName) -y" -Wait
        & $choco install $($AppName) -y | Tee-Object -FilePath $($localLogFile) -Append
    }
    else {
        throw "$($AppName) not found."
        exit 1
    }
}
catch
{
	Write-Log "ERROR: Application '$($AppName)' could not be installed.
	Reason: $_"
	Write-Warning "ERROR: Application '$($AppName)' could not be installed.
	Reason: $_"
    exit 1
}

Write-Log "Finish Logging."

<#
# Finalizing
#>
if($UploadLog){
    # Upload logFile
    try{
        Copy-Item "$($localLogFile)" -Destination "$($logFilePath)"
    }
    catch{
        Write-Warning "ERROR: Logfile '$($localLogFile)' could not be uploaded to Deployment-Server.
        Reason: $_"
    }
}

if($DeleteLogfile){
    # Delete local logFile
    try{
        Remove-Item "$($localLogFile)" -Force
    }
    catch{
        Write-Warning "ERROR: Logfile '$($localLogFile)' could not be deleted.
        Reason: $_"
    }
}
