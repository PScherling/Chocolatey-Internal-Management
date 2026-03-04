<#
.SYNOPSIS
    Automates downloading and updating of Microsoft Office installation sources for multiple editions using the Office Deployment Tool (ODT).

.DESCRIPTION
    This PowerShell script refreshes local Microsoft Office installation packages for different versions and editions 
    (e.g., Office 2019, Office LTSC 2021, and Office LTSC 2024 - both Standard and Pro Plus).  
    It is designed to maintain a centralized, up-to-date repository of Office installers used in enterprise or deployment environments such as MDT or SCCM.

    The script:
    - Iterates through a predefined list of Office editions and versions.
    - Deletes any existing "Office" folder to remove outdated installation files.
    - Executes `setup.exe /download <config.xml>` for each product XML definition file to fetch the latest binaries.
    - Logs all operations (status, warnings, and errors) to a timestamped log file stored in `.\Logs\UpdateMSOffice\`.
    - Displays a stylized ASCII banner to visually indicate process start.

    This process ensures all Office builds in the local repository remain current and deployment-ready for offline or automated installations.

    Typical use cases:
    - Updating deployment share content before MDT or SCCM task sequences.
    - Periodic maintenance of software sources on file shares.
    - Automation of Office ODT content management.

.LINK
    https://learn.microsoft.com/en-us/deployoffice/overview-office-deployment-tool  
    https://github.com/microsoft/Office-IT-Pro-Deployment-Scripts
    https://github.com/PScherling
    
.NOTES
          FileName: UpdateMSOffice.ps1
          Solution: Auto-Update MS Offcie Packages
          Author: Patrick Scherling
          Contact: @Patrick Scherling
          Primary: @Patrick Scherling
          Created: 2025-07-18
          Modified: 2026-03-04

          Version - 0.0.1 - () - Finalized functional version 1.
          Version - 0.0.2 - () - Adapting Path Structure
          Version - 0.0.3 - () - Excludiong Office 2019
		  Version - 0.0.4 - (2026-02-25) - Adaption for Chocolatey environments
          Version - 0.0.5 - (2026-02-25) - Refactor to work with 'UpdateSoftwarePackages.ps1'
          Version - 0.0.6 - (2026-02-26) - Minor Bug-Fixes and improve compatibillity with 'UpdateSoftwarePAckages.ps1'
          Version - 0.0.7 - (2026-03-03) - Changing the way of creating zip archive. (Changing to use 7zip instead of compress-archive)
          Version - 0.0.8 - (2026-03-04) - Adaption 7-Zip CLI Arguments to silence the console output.
          

          TODO:

.Requirements
    - Office Deployment Tool (setup.exe)
    - Internet access to Microsoft CDN
    - Write permissions to local storage path (default: `E:\ChocoManage\temp\Downloads`)	  
		
.Example
    PS> .\UpdateMSOffice.ps1 
    Downloads and refreshes all defined Microsoft Office editions to ensure updated installation sources.

    PS> .\UpdateMSOffice.ps1 -Verbose
    Runs the update process with verbose console output.

    Typical Scheduled Task:
    powershell.exe -ExecutionPolicy Bypass -File "C:\Scripts\UpdateMSOffice.ps1"
    Automates Office source updates as a nightly scheduled job.
#>
param(
    [Parameter(Mandatory = $false)] [string] $OfficeKey,                                                                     # e.g. LTSC2021ProPlus, LTSC2021Standard, LTSC2024ProPlus, LTSC2024Standard
    [Parameter(Mandatory = $false)] [string] $BaseDir = "E:\ChocoManage",
    [Parameter(Mandatory = $false)] [switch] $RunNotStandalone,                                                              # e.g. in case you want to run this script not in standalone mode
    [Parameter(Mandatory = $false)] [switch] $ReturnObject,                                                                  # called to return a real object
    [Parameter(Mandatory = $false)] [switch] $WhatIf                                                                         # Switch to run everything except downloading
)



# Config
$filetimestamp 					= Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$logDir							= "$($BaseDir)\Logs\UpdateSoftwarePackages"
$logPath 						= Join-Path -Path "$($logDir)" -ChildPath "UpdateMSOffice_$($filetimestamp).log"
$downloadPath 					= "$($BaseDir)\temp\Downloads"     # still needed?
$success                        = $true
$officeVersion                  = $null
$packageZip                     = $null

if($RunNotStandalone){
    # DEBUG
    #Write-Host -ForegroundColor Magenta "DEBUG: $($BaseDir) | $($logDir) | $($downloadPath)"
    if($OfficeKey -like "*2019*Standard" -or $OfficeKey -like "*2019*Std"){
        $installations = @(
            @{ Name = "Office 2019 Standard"; Path = "$($downloadPath)\Office2019"; XML = "$($downloadPath)\OfficeLTSC2021\office_19_std.xml" }
        )
    }
    elseif($OfficeKey -like "*2019*ProPlus" -or $OfficeKey -like "*2019*Pro Plus"){
        $installations = @(
            @{ Name = "Office 2019 Pro Plus"; Path = "$($downloadPath)\Office2019"; XML = "$($downloadPath)\OfficeLTSC2021\office_19_proplus.xml" }
        )
    }
    elseif($OfficeKey -like "*LTSC*2021*Standard" -or $OfficeKey -like "*LTSC*2021*Std"){
        $installations = @(
            @{ Name = "Office LTSC 2021 Standard"; Path = "$($downloadPath)\OfficeLTSC2021"; XML = "$($downloadPath)\OfficeLTSC2021\office_ltsc_21_std.xml" }
        )
    }
    elseif($OfficeKey -like "*LTSC*2021*ProPlus" -or $OfficeKey -like "*LTSC*2021*Pro Plus" -or $OfficeKey -like "*LTSC*2021*Pro-Plus"){
        $installations = @(
            @{ Name = "Office LTSC 2021 Pro Plus"; Path = "$($downloadPath)\OfficeLTSC2021"; XML = "$($downloadPath)\OfficeLTSC2021\office_ltsc_21_proplus.xml" }
        )
    }
    elseif($OfficeKey -like "*LTSC*2024*Standard" -or $OfficeKey -like "*LTSC*2024*Std"){
        $installations = @(
            @{ Name = "Office LTSC 2024 Standard"; Path = "$($downloadPath)\OfficeLTSC2024"; XML = "$($downloadPath)\OfficeLTSC2024\office_ltsc_24_std.xml" }
        )
    }
    elseif($OfficeKey -like "*LTSC*2024*ProPlus" -or $OfficeKey -like "*LTSC*2024*Pro Plus" -or $OfficeKey -like "*LTSC*2024*Pro-Plus"){
        $installations = @(
            @{ Name = "Office LTSC 2024 Pro Plus"; Path = "$($downloadPath)\OfficeLTSC2024"; XML = "$($downloadPath)\OfficeLTSC2024\office_ltsc_24_proplus.xml" }
        )
    }
    else {
        throw "Unknown OfficeKey '$OfficeKey'"
    }
}
else{
    $installations = @(
        #@{ Name = "Office 2019 Pro Plus"; Path = "$($downloadPath)\Office2019ProPlus"; XML = "$($downloadPath)\Office2019ProPlus\office_19_proplus.xml" },
        #@{ Name = "Office 2019 Standard"; Path = "$($downloadPath)\Office2019Standard"; XML = "$($downloadPath)\Office2019Standard\office_19_std.xml" },
        @{ Name = "Office LTSC 2021 Pro Plus"; Path = "$($downloadPath)\OfficeLTSC2021"; XML = "$($downloadPath)\OfficeLTSC2021\office_ltsc_21_proplus.xml" },
        @{ Name = "Office LTSC 2021 Standard"; Path = "$($downloadPath)\OfficeLTSC2021"; XML = "$($downloadPath)\OfficeLTSC2021\office_ltsc_21_std.xml" },
        @{ Name = "Office LTSC 2024 Pro Plus"; Path = "$($downloadPath)\OfficeLTSC2024"; XML = "$($downloadPath)\OfficeLTSC2024\office_ltsc_24_proplus.xml" },
        @{ Name = "Office LTSC 2024 Standard"; Path = "$($downloadPath)\OfficeLTSC2024"; XML = "$($downloadPath)\OfficeLTSC2024\office_ltsc_24_std.xml" }
    )
    
}

if (-not (Test-Path $logDir)) {
    Write-Host "Log Directory not found. Creating '$($logDir)'"
    try{
        New-Item -ItemType Directory -Path $logDir | Out-Null
    } catch{
        #Write-Error "Download directory could not be created. $_"
        throw "ERROR: Log directory could not be created. $_"
        exit 1
    }
}

if (-not (Test-Path $logPath)) {
    #Write-Host "Creating '$($logPath)'"
    try{
        New-Item -ItemType File -Path $logPath | Out-Null
    } catch{
        #Write-Error "Download directory could not be created. $_"
        throw "ERROR: Log file could not be created. $_"
        exit 1
    }
}

if (-not (Test-Path $downloadPath)) {
    Write-Host "Download Directory not found. Creating '$($downloadPath)'"
    try{
        New-Item -ItemType Directory -Path $downloadPath | Out-Null
    } catch{
        throw "ERROR: Download directory could not be created. $_"
        exit 1
    }
}



# Logging function
function Write-Log {
    param([string]$msg)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $msg" | Out-File -FilePath $logPath -Append
}

function Get-OfficeContentVersion {
    param(
        [Parameter(Mandatory)] [string] $OfficeRootPath   # e.g. E:\...\OfficeLTSC2021\ProPlus\Office
    )

    $dataPath = Join-Path $OfficeRootPath "Data"
    if (-not (Test-Path $dataPath)) {
        return $null
    }

    $verFolder = Get-ChildItem -Path $dataPath -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
        Sort-Object Name -Descending |
        Select-Object -First 1

    if ($verFolder) { return $verFolder.Name }
    return $null
}

function New-OfficePackageZip {
    param(
        [Parameter(Mandatory)] [string] $ItemPath,      # e.g. E:\...\Downloads\OfficeLTSC2021ProPlus
        [Parameter(Mandatory)] [string] $OfficeName,    # e.g. OfficeLTSC2021
        [Parameter(Mandatory)] [string] $Edition,       # ProPlus or Standard
        [Parameter(Mandatory)] [string] $Version,       # 16.0.xxxxx.xxxxx
        [Parameter(Mandatory)] [string] $DownloadPath
    )

    $zipName = "{0}_{1}_{2}.zip" -f $OfficeName, $Edition, $Version
    $zipPath = Join-Path $DownloadPath $zipName

    # Build a temporary staging folder to control zip content
    $stageRoot = Join-Path $env:TEMP ("OfficeZipStage_" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null

    try {
        # Expected layout in ItemPath:
        # setup.exe
        # office_xxx.xml
        # ProPlus\Office   or Standard\Office

        $setupExe = Join-Path $ItemPath "setup.exe"
        if (-not (Test-Path $setupExe)) {
            throw "setup.exe not found in '$ItemPath'"
        }

        Copy-Item $setupExe -Destination (Join-Path $stageRoot "setup.exe") -Force

        # Copy XML(s) - if there are multiple, copy all office*.xml
        Get-ChildItem -Path $ItemPath -Filter "*.xml" -File -ErrorAction SilentlyContinue | ForEach-Object {
            Copy-Item $_.FullName -Destination (Join-Path $stageRoot $_.Name) -Force
        }

        $editionFolder = Join-Path $ItemPath $Edition
        if (-not (Test-Path $editionFolder)) {
            throw "Edition folder '$editionFolder' not found"
        }

        Copy-Item $editionFolder -Destination (Join-Path $stageRoot $Edition) -Recurse -Force

        if (Test-Path $zipPath) {
            Remove-Item $zipPath -Force
        }

        #Compress-Archive -Path (Join-Path $stageRoot '*') -DestinationPath $zipPath -Force
        
        $sevenZip = "C:\Program Files\7-Zip\7z.exe"
        if (-not (Test-Path $sevenZip)) {
            throw "7-Zip not found at '$sevenZip'"
        }

        $arguments = @(
            "a"
            "-tzip"
            "-mx=5"
            "-bb0"  # lowest log level
            "-bso0" # suppress standard output
            "-bse0" # suppress error output
            "-bsp0" # suppress progress indicator
            $zipPath
            "*"
        )

        $proc = Start-Process -FilePath $sevenZip `
                              -ArgumentList $arguments `
                              -WorkingDirectory $stageRoot `
                              -Wait `
                              -PassThru `
                              -NoNewWindow

        if ($proc.ExitCode -eq 0) {
            Write-Host -ForegroundColor Green "    Archive created successfully"
        }
        elseif($proc.ExitCode -eq 1) {
            Write-Host -ForegroundColor Yellow "    Warning (Non fatal error): For example, one or more files were locked by some other application, so they were not compressed. Exit code: $($proc.ExitCode)"
        }
        elseif ($proc.ExitCode -ne 0 -or $proc.ExitCode -ne 1) {
            throw "7-Zip failed with exit code $($proc.ExitCode)"
        }

        return $zipPath
    }
    finally {
        if (Test-Path $stageRoot) {
            Remove-Item $stageRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}


Write-Log "=== Starting progress... ==="
if(-not $RunNotStandalone){
    Clear-Host
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
}

foreach ($item in $installations) {
    Write-Log "--------------------------------------------------------------------------------"
    Write-Log "Processing: $($item.Name)"
    #Write-Log "Changing directory to: $($item.Path)"

    if(-not $RunNotStandalone){
        Write-Host "--------------------------------------------------------------------------------" -ForegroundColor Cyan
        Write-Host "    Processing: $($item.Name)" -ForegroundColor Magenta
        #Write-Host "    Changing directory to: $($item.Path)" -ForegroundColor Gray
    }


    #Set-Location $item.Path

    # Remove Office folder
	if($item.Name -like "*Pro Plus*"){
        $edition = "ProPlus"
        $officeRootFull = Join-Path $item.Path "ProPlus\Office"
		#$OfficePath = ".\ProPlus\Office"
	}
	elseif($item.Name -like "*Standard*"){
        $edition = "Standard"
        $officeRootFull = Join-Path $item.Path "Standard\Office"
		#$OfficePath = ".\Standard\Office"
	}
	else{
		Write-Log "ERROR: Cannot determine edition for '$($item.Name)'"
        $success = $false
		Write-Host -ForegroundColor Red "     ERROR: Cannot determine edition for '$($item.Name)'"
	}

    # DEBUG
	#Write-Host -ForegroundColor Magenta "DEBUG: $($officeRootFull)"

    if (Test-Path $officeRootFull) {
        Write-Host "    Removing existing 'Office' folder..." -ForegroundColor Gray
        Write-Log "Removing existing 'Office' folder..."
        if($WhatIf){
            Write-Host "    WHATIF Enabled -> Removing existing 'Office' folder will be ignored!" -ForegroundColor Yellow
            Write-Log "WARNING: WHATIF Enabled -> Removing existing 'Office' folder will be ignored!"
        }
        else{
            try{
                Remove-Item -Path "$($officeRootFull)" -Recurse -Force #-Verbose
            }
            catch{
                Write-Warning "Folder could not be removed - $_"
                Write-Log "Folder could not be removed - $_"
                exit 1
            }
        }
    } else {
        Write-Host "    'Office' folder not found, skipping removal." -ForegroundColor DarkGray
        Write-Log "WARNING: 'Office' folder not found, skipping removal."
    }

    # Start download
    Write-Log "Starting download with: $($item.XML)"
    Write-Host "    Starting download with: $($item.XML)" -ForegroundColor Green
    Write-Host "    This may take some time..." -ForegroundColor Yellow

    if($WhatIf){
        Write-Host "    WHATIF Enabled -> Download of new Office files will be ignored!" -ForegroundColor Yellow
        Write-Log "WARNING: WHATIF Enabled -> Download of new Office files will be ignored!"
    }
    else{
        try{
            Start-Process -FilePath "$($item.Path)\setup.exe" -ArgumentList "/download $($item.XML)" -WorkingDirectory $item.Path -Wait
        } catch{
            $success = $false
            Write-Error "Download of new Office files could not be started - $_"
            Write-Log "ERROR: Download of new Office files could not be started - $_"
        }
    }

    if($success){
        Write-Log "Finished: $($item.Name)"
        Write-Host "    Finished: $($item.Name)" -ForegroundColor Green
    } else{
        Write-Log "Finished with errors: $($item.Name)"
        Write-Host "    Finished with errors: $($item.Name)" -ForegroundColor Red
    }
    if($RunNotStandalone){
        $officeVersion = Get-OfficeContentVersion -OfficeRootPath $officeRootFull
        if (-not $officeVersion) {
            Write-Log "ERROR: Could not detect Office content version in '$officeRootFull'"
            Write-Host "    ERROR: Could not detect Office content version." -ForegroundColor Red
            $success = $false
        }

        $packageZip = $null
        #if ($success -and -not $WhatIf) {
        if ($success) {
            
            
            $zipFile = Get-ChildItem -Filter "*.zip" -Path "$($downloadPath)" | where-object { $_.BaseName -eq "$($software.SoftwareName)_$($edition)_$($officeVersion)" }
            
            if(-not $zipFile){
                try {
                    $packageZip = New-OfficePackageZip `
                        -ItemPath $item.Path `
                        -OfficeName (($item.Name -replace ' ', '') -replace 'ProPlus|Standard','') `
                        -Edition $edition `
                        -Version $officeVersion `
                        -DownloadPath $downloadPath

                    $packageFileName = if ($packageZip) { [System.IO.Path]::GetFileName($packageZip) } else { $null }

                    Write-Log "Created Office package zip: $packageZip"
                    Write-Host "    Created package zip: $packageZip" -ForegroundColor Green
                }
                catch {
                    $success = $false
                    Write-Log "ERROR: Failed to create Office zip package - $_"
                    Write-Host "    ERROR: Failed to create Office zip package - $_" -ForegroundColor Red
                }
                
            }
            else{
                Write-Host "    Package file for version '$($officeVersion)' already created. Nothing to do." -ForegroundColor DarkGray
                Write-Log "Package file for version '$($officeVersion)' already created. Nothing to do."
                
                $packageZip = $zipFile.FullName
                $packageFileName = $zipFile.Name
            }
        }
    }
    
    if ($ReturnObject) {
        return [pscustomobject]@{
            Success         = [bool]$success
            Product         = $item.Name
            Version         = $officeVersion
            SourceFolder    = $item.Path
            PackageFile     = $packageZip
            PackageFileName = $packageFileName
            WhatIf          = [bool]$WhatIf
        }
    }
}



Write-Log "=== Finished progress... ==="
Write-Host "`nAll operations completed." -ForegroundColor Cyan
