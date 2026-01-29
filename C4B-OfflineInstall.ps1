<#
.SYNOPSIS


.DESCRIPTION


.LINK
    https://community.chocolatey.org/packages/chocolatey
    https://chocolatey.org/install
    https://community.chocolatey.org/courses/installation/installing?method=completely-offline-install
	https://docs.chocolatey.org/en-us/licensed-extension/setup/
    https://docs.chocolatey.org/en-us/central-management/setup/
    https://docs.chocolatey.org/en-us/central-management/setup/website/#scenario-three
    https://docs.chocolatey.org/en-us/central-management/setup/service/#scenario-three
    https://docs.chocolatey.org/en-us/central-management/setup/database/#scenario-one
    https://help.sonatype.com/en/install-nexus-repository.html
	https://learn.microsoft.com/de-de/troubleshoot/sql/releases/download-and-install-latest-updates
	https://learn.microsoft.com/de-de/troubleshoot/sql/releases/download-and-install-latest-updates#sql-server-2025
	https://learn.microsoft.com/de-de/powershell/module/microsoft.powershell.management/get-service?view=powershell-7.5
	https://github.com/PScherling
	
.NOTES
          FileName: C4B-OfflineInstall.ps1
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
    [ValidateScript({
        if (-not (Test-Path (Convert-Path $_))) {
            throw "License file does not exist at '$($_)'. Please provide a valid -LicensePath"
        }
        try {
            [xml]$License = Get-Content $_
            $Expiry = Get-Date $License.license.expiration
            if (-not $Expiry -or $Expiry -lt (Get-Date)) {throw}
        } catch {
            throw "License '$($_)' is not valid.$(if ($Expiry) {" It expired at '$($Expiry)'."})"
        }
        $true
    })]
    [Parameter(Mandatory)][string]$LicensePath = $(
        if (Test-Path $PSScriptRoot\files\chocolatey.license.xml) {
            # Offline setup has been run, we should use that license.
            Join-Path $PSScriptRoot "files\chocolatey.license.xml"
        } elseif (Test-Path $env:ChocolateyInstall\license\chocolatey.license.xml) {
            # Chocolatey is already installed, we can use that license.
            Join-Path $env:ChocolateyInstall "license\chocolatey.license.xml"
        } else {
            # Prompt the user for the license.
            $Wshell = New-Object -ComObject Wscript.Shell
            $null = $Wshell.Popup('You will need to provide the license file location. Please select your Chocolatey License in the next file dialog.')
            $null = [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms")
            $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
            $OpenFileDialog.initialDirectory = "$env:USERPROFILE\Downloads"
            $OpenFileDialog.filter = 'All Files (*.*)| *.*'
            $null = $OpenFileDialog.ShowDialog()

            $OpenFileDialog.filename
        }
    ),                                                                # e.g. D:\License.xml
    #[Parameter(Mandatory)][string]$ServerFqdn,                        # e.g. psc-c4bsrv.local
    [Parameter(Mandatory)][string]$NexusRepoName,                     # e.g. nuget-hosted
    [Parameter(Mandatory)][string]$BusinessLicenseGuid,               # e.g. You get this from the chocolatey.license.xml file
    [Parameter(Mandatory)][string]$NexusRepoKey,                      # e.g. You get this from http://localhost:8081/#user/NuGetApiToken
    [Parameter(Mandatory)][string]$DBUser,                            # e.g. DB User Name | Default is 'ChocoUser'
    [Parameter(Mandatory)][string]$DBUserPassword,                    # e.g. Provide a super hard password!
    [Parameter(Mandatory)][string]$LocalAdmin,                        # e.g. Local Windows Admin | Default is 'sysadmineuro'
    [Parameter][switch]$UseADLoginforDB                               # e.g. Use this Switch Parameter if you want to enable DB Login with AD Credentials
    
)

$ErrorActionPreference = 'Stop'

# Require admin
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
  throw "Run PowerShell as Administrator."
}

# ====== YOUR ENV SETTINGS ======
# Find FDQN for current machine
$ServerFqdn = [System.Net.Dns]::GetHostName()
$domainName = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().DomainName

if(-Not $ServerFqdn.endswith($domainName)) {
    $ServerFqdn += "." + $domainName
}

$NexusNuGetUrl      = "http://$($ServerFqdn):8081/repository/$($NexusRepoName)/"
$CertThumbprint     = (Get-ChildItem Cert:\LocalMachine\My |
    Where-Object {$_.Subject -like "*CN=$ServerFqdn*"} |
    Sort-Object NotAfter -Descending |
    Select-Object -First 1 -ExpandProperty Thumbprint)

# CCM defaults (adjust if you like)
$CcmDbName          = "ChocolateyMGMTDB"
$SqlInstance        = ".\SQLEXPRESS"

# CCM service port (commonly used; confirm with your CCM docs/config)
$CcmServicePort     = 24020

# CCM Service URL clients will talk to
$CcmServiceUrl      = "https://$($ServerFqdn):$($CcmServicePort)/ChocolateyManagementService"

$pkgDir             = "D:\SetupFiles\Packages"

$LicensePath = Convert-Path $LicensePath
$licDir = Join-Path $env:ProgramData "chocolatey\license"


function Add-DatabaseUserAndRoles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string] $Username,

        [Parameter(Mandatory=$true)]
        [string] $DatabaseName,

        [Parameter(Mandatory=$false)]
        [string] $DatabaseServer = 'localhost\SQLEXPRESS',

        [Parameter(Mandatory=$false)]
        [string[]] $DatabaseRoles = @('db_datareader'),

        [Parameter(Mandatory=$false)]
        [string] $DatabaseServerPermissionsOptions = 'Trusted_Connection=true;',

        [Parameter(Mandatory=$false)]
        [switch] $CreateSqlUser,

        [Parameter(Mandatory=$false)]
        [string] $SqlUserPassword
    )

    $LoginOptions = "FROM WINDOWS WITH DEFAULT_DATABASE=[$DatabaseName]"
    if ($CreateSqlUser) {
        $LoginOptions = "WITH PASSWORD='$SqlUserPassword', DEFAULT_DATABASE=[$DatabaseName], CHECK_EXPIRATION=OFF, CHECK_POLICY=OFF"
    }

    $addUserSQLCommand = @"
USE [master]
IF EXISTS(SELECT * FROM msdb.sys.syslogins WHERE UPPER([name]) = UPPER('$Username'))
BEGIN
    DROP LOGIN [$Username]
END

CREATE LOGIN [$Username] $LoginOptions

USE [$DatabaseName]
IF EXISTS(SELECT * FROM sys.sysusers WHERE UPPER([name]) = UPPER('$Username'))
BEGIN
    DROP USER [$Username]
END

CREATE USER [$Username] FOR LOGIN [$Username]

"@

    foreach ($DatabaseRole in $DatabaseRoles) {
        $addUserSQLCommand += @"

ALTER ROLE [$DatabaseRole] ADD MEMBER [$Username]
"@
    }

    Write-Output "Adding $UserName to $DatabaseName with the following permissions: $($DatabaseRoles -Join ', ')"
    Write-Debug "running the following: \n $addUserSQLCommand"


    $Connection = New-Object System.Data.SQLClient.SQLConnection
    $Connection.ConnectionString = "server=$($DatabaseServer);database=master;$($DatabaseServerPermissionsOptions)"
    $Connection.Open()
    $Command = New-Object System.Data.SQLClient.SQLCommand
    $Command.CommandText = $addUserSQLCommand
    $Command.Connection = $Connection
    $Command.ExecuteNonQuery()
    $Connection.Close()
}



# ====== START ======
# Initialize environment, ensure Chocolatey For Business, etc.
$Licensed = ($($(choco.exe)[0] -match "^Chocolatey (?<Version>\S+)\s*(?<LicenseType>Business)?$") -and $Matches.LicenseType)
$InstalledLicensePath = "$env:ChocolateyInstall\license\chocolatey.license.xml"
if (-not $Licensed) {
    if (-not (Test-Path $InstalledLicensePath)) {
        if (-not (Test-Path $env:ChocolateyInstall\license)) {
            $null = New-Item $env:ChocolateyInstall\license -ItemType Directory
        }
        Copy-Item $LicensePath $InstalledLicensePath -Force
    }
    $ExtensionSource = if (Test-Path $PSScriptRoot\files\chocolatey.extension.*.nupkg) {
        Convert-Path $PSScriptRoot\files\
    } else {
        'https://licensedpackages.chocolatey.org/api/v2/'
    }
    choco install chocolatey.extension --source $ExtensionSource --params="'/NoContextMenu'" --confirm
}

Write-Host "Staring installation of Chocolatey 4 Business"
if($CertThumbprint){
    Write-Host -ForegroundColor Green "We are good to go"

    if(!(Test-Path "$($pkgDir)")){
        New-Item "$($pkgDir)" -ItemType Directory | Out-Null
    }

    # ====== Download packages
    # Download Chocolatey community related items, no internalization necessary
    Write-Host "Download Chocolatey community related items, no internalization necessary"
    Write-Host "Download chocolatey and chocolateygui"
    choco download chocolatey chocolateygui --force --source="'https://community.chocolatey.org/api/v2/'" --output-directory="$($pkgDir)"

    # This is for other Community Related Items
    Write-Host "Download dotnet4.5.2 dotnetfx"
    choco download dotnet4.5.2 dotnetfx --force --internalize --internalize-all-urls --append-use-original-location --source="'https://community.chocolatey.org/api/v2/'" --output-directory="$($pkgDir)"

    # This is for SQL Server Express
    # Not necessary if you already have SQL Server
    Write-Host "Download sql-server-express and sql-server-management-studio"
    @('sql-server-express','sql-server-management-studio') | Foreach-Object {
        choco download $_ --force --internalize --internalize-all-urls --append-use-original-location --source="'https://community.chocolatey.org/api/v2/'" --output-directory="$($pkgDir)"
    }

    # We must use the 8.x.x versions of these packages, so we need to download/internalize these specific items.  At the time of publishing, the most recent version of this package is 8.0.8, but later package versions (within the 8.x.x release) are expected to work.
    Write-Host "Download dotnet-8.0-runtime and dotnet-8.0-aspnetruntime"
    @('dotnet-8.0-runtime', 'dotnet-8.0-aspnetruntime') | Foreach-Object {
        choco download $_ --version 8.0.8 --force --internalize --internalize-all-urls --append-use-original-location --source="'https://community.chocolatey.org/api/v2/'" --output-directory="$($pkgDir)"
    }

    # Starting with v0.9.0 of the CCM Website package, it uses dotnet-aspnetcoremodule-v2. At the time of publishing, the most recent version of this package 18.0.24201, but later package versions (within the 18.x.x release) are expected to work
    Write-Host "Download dotnet-aspnetcoremodule-v2"
    choco download dotnet-aspnetcoremodule-v2 --version 18.0.24201 --force --internalize --internalize-all-urls --append-use-original-location --source="'https://community.chocolatey.org/api/v2/'" --output-directory="$($pkgDir)"

    # ====== Download Licensed Packages
    ## DO NOT RUN WITH `--internalize` and `--internalize-all-urls` - see https://github.com/chocolatey/chocolatey-licensed-issues/issues/155
    Write-Host "Download chocolatey-agent, chocolatey.extension, chocolatey-management-database, chocolatey-management-service, chocolatey-management-web"
    choco download chocolatey-agent chocolatey.extension chocolatey-management-database chocolatey-management-service chocolatey-management-web --force --source="'https://licensedpackages.chocolatey.org/api/v2/'" --ignore-dependencies --output-directory="$($pkgDir)"  --user="'user'" --password="$($BusinessLicenseGuid)"

    # ====== Push downloaded packages to repository
    Write-Host "Push downloaded packages to repository"
    Get-ChildItem "$($pkgDir)" -Filter *.nupkg | Foreach-Object {
        choco push "$($_.FullName)" --source="$($NexusNuGetUrl)" --api-key="$($NexusRepoKey)"
    }

    # Configure new internal repository
    Write-Host "Configure new internal repository"
    choco source add -n="nexus-internal" -s="$NexusNuGetUrl" --priority=1

    # Remove public repository
    Write-Host "Remove public repository"
    choco source disable -n="chocolatey"

    # ====== Install License
    Write-Host "Install License"
    New-Item -ItemType Directory -Path $licDir -Force | Out-Null
    Copy-Item "$($LicensePath)" "$($licDir)" -Force
    
    # Install the licensed extension from Nexus
    Write-Host "Install chocolatey.extension"
    choco install chocolatey.extension -y --source="$($NexusNuGetUrl)"

    # ====== Install SQL Server and Management
    Write-Host "Install sql-server-express"
    choco install sql-server-express -y --source="$($NexusNuGetUrl)"
    Write-Host "Install sql-server-management-studio"
    choco install sql-server-management-studio -y --source="$($NexusNuGetUrl)"

    
    if(Get-Service | Where-Object Name -match "MSSQL\$\w+|MSSQLSERVER"){
        Write-Host -ForegroundColor Green "We are good to go"

        # ====== Prepare Database
        # https://docs.microsoft.com/en-us/sql/tools/configuration-manager/tcp-ip-properties-ip-addresses-tab
        Write-Host "SQL Server: Configuring Remote Access on SQL Server Express."
        $assemblyList = 'Microsoft.SqlServer.Management.Common', 'Microsoft.SqlServer.Smo', 'Microsoft.SqlServer.SqlWmiManagement', 'Microsoft.SqlServer.SmoExtended'

        foreach ($assembly in $assemblyList) {
            $assembly = [System.Reflection.Assembly]::LoadWithPartialName($assembly)
        }

        $wmi = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer # connects to localhost by default
        $instance = $wmi.ServerInstances | Where-Object { $_.Name -eq 'SQLEXPRESS' }

        $np = $instance.ServerProtocols | Where-Object { $_.Name -eq 'Np' }
        $np.IsEnabled = $true
        $np.Alter()

        $tcp = $instance.ServerProtocols | Where-Object { $_.Name -eq 'Tcp' }
        $tcp.IsEnabled = $true
        $tcp.Alter()

        
        $tcpIpAll = $tcp.IpAddresses | Where-Object { $_.Name -eq 'IpAll' }

        $tcpDynamicPorts = $tcpIpAll.IpAddressProperties | Where-Object { $_.Name -eq 'TcpDynamicPorts' }
        $tcpDynamicPorts.Value = ""
        $tcp.Alter()

        $tcpPort = $tcpIpAll.IpAddressProperties | Where-Object { $_.Name -eq 'TcpPort' }
        $tcpPort.Value = "1433"
        $tcp.Alter()

        # TODO: THIS LINE IS VERSION DEPENDENT! Replace MSSQL16 with whatever version you have
        Write-Host "SQL Server: Setting Mixed Mode Authentication."
        $sqlpkg = choco search sql-server-express --exact --limitoutput
        $pkginfo = "$($sqlpkg)" -split "\|"
        $pkgversion = $pkginfo[1]
        Write-Host "Installed SQL Server Version: $sqlpkg"
        <#$inst = (get-itemproperty 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server').InstalledInstances
        foreach ($i in $inst)
        {
            $p = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL').$i
            (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$p\Setup").Edition
            (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$p\Setup").Version
        }
        #>
        if($pkgversion -match "2016.*"){
            New-ItemProperty 'HKLM:\Software\Microsoft\Microsoft SQL Server\MSSQL13.SQLEXPRESS\MSSQLServer\' -Name 'LoginMode' -Value 2 -Force
        }
        elseif($pkgversion -match "2017.*"){
            New-ItemProperty 'HKLM:\Software\Microsoft\Microsoft SQL Server\MSSQL14.SQLEXPRESS\MSSQLServer\' -Name 'LoginMode' -Value 2 -Force
        }
        elseif($pkgversion -match "2019.*"){
            New-ItemProperty 'HKLM:\Software\Microsoft\Microsoft SQL Server\MSSQL15.SQLEXPRESS\MSSQLServer\' -Name 'LoginMode' -Value 2 -Force
        }
        elseif($pkgversion -match "2022.*"){
            New-ItemProperty 'HKLM:\Software\Microsoft\Microsoft SQL Server\MSSQL16.SQLEXPRESS\MSSQLServer\' -Name 'LoginMode' -Value 2 -Force
        }
        elseif($pkgversion -match "2025.*"){
            New-ItemProperty 'HKLM:\Software\Microsoft\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQLServer\' -Name 'LoginMode' -Value 2 -Force
        }
        # VERSION DEPENDENT ABOVE

        Write-Host "SQL Server: Forcing Restart of Instance."
        Restart-Service -Force 'MSSQL$SQLEXPRESS'

        Write-Host "SQL Server: Setting up SQL Server Browser and starting the service."
        Set-Service "SQLBrowser" -StartupType Automatic
        Start-Service "SQLBrowser"

        Write-Host "Firewall: Enabling SQLServer TCP port 1433."
        netsh advfirewall firewall add rule name="SQL Server 1433" dir=in action=allow protocol=TCP localport=1433 profile=any enable=yes service=any
        #New-NetFirewallRule -DisplayName "Allow inbound TCP Port 1433" –Direction inbound –LocalPort 1433 -Protocol TCP -Action Allow

        Write-Host "Firewall: Enabling SQL Server browser UDP port 1434."
        netsh advfirewall firewall add rule name="SQL Server Browser 1434" dir=in action=allow protocol=UDP localport=1434 profile=any enable=yes service=any
        #New-NetFirewallRule -DisplayName "Allow inbound UDP Port 1434" –Direction inbound –LocalPort 1434 -Protocol UDP -Action Allow


        # ====== Install Chocolatey Central Management Database Package
        $ConnStr = "Server=$($SqlInstance);Database=$($CcmDbName);TrustServerCertificate=True;"
        Write-Host "Server Connection-String: $($ConnStr)"
        choco install chocolatey-management-database -y --source="$($NexusNuGetUrl)" --package-parameters="'/ConnectionString:$($ConnStr);Trusted_Connection=True;'" 
        #--package-parameters='/ConnectionString=""Server=Localhost\SQLEXPRESS;Database='$($CcmDbName)';Trusted_Connection=true;""'


        # Please choose from one of the three listed account types below. The commands will grant database permissions to a user account of your choice. 
        # This account will be used in your Connection String for the CCM Service and Web package installs ahead.
        # Add Sql Server Login / User:
        Write-Host "Add Sql Server Login / User"
        Add-DatabaseUserAndRoles -DatabaseName "$($CcmDbName)" -Username "$($DBUser)" -SqlUserPassword "$($DBUserPassword)" -CreateSqlUser  -DatabaseRoles @('db_datareader', 'db_datawriter')

        # Add Local Windows User:
        Write-Host "Add Local Windows User"
        Add-DatabaseUserAndRoles -DatabaseName "$($CcmDbName)" -Username "$(hostname)\$($LocalAdmin)" -DatabaseRoles @('db_datareader', 'db_datawriter')

        # Add Active Directory Domain User to a default instance of SQL Server:
        if($UseADLoginforDB){
            Write-Host "Add Active Directory Domain User to a default instance of SQL Server"
            $domainuser = Read-Host -Prompt "Enter User Name (domain\user)"
            Add-DatabaseUserAndRoles -DatabaseServer 'localhost' -DatabaseName "$($CcmDbName)" -Username "$($domainuser)" -DatabaseRoles @('db_datareader', 'db_datawriter')
        }
        
        # ====== Install CCM Service (the API / communication layer)
        Write-Host "Install CCM Service (the API / communication layer)"
        choco config set --name="centralManagementServiceUrl" --value="$($CcmServiceUrl)"
        choco install chocolatey-management-service -y --source="$($NexusNuGetUrl)" --package-parameters-sensitive="'/ConnectionString:$($ConnStr);User ID=$($DBUser);Password=$($DBUserPassword); /PortNumber:$($CcmServicePort) /CertificateThumbprint:$($CertThumbprint)'"

        Write-Host "Set Firewall Rule"
        New-NetFirewallRule -DisplayName "CCM Service $($CcmServicePort)" -Direction Inbound -Protocol TCP -LocalPort $($CcmServicePort) -Action Allow

        Get-NetTCPConnection -LocalPort $CcmServicePort -State Listen
        #Get-Service -DisplayName "Chocolatey Management Service" | Out-Null
        Get-Service -DisplayName "Chocolatey Management Service" -ErrorAction SilentlyContinue | Out-Null


        if(Get-Service | Where-Object DisplayName -match "Chocolatey.*Management.*Service"){
            Write-Host -ForegroundColor Green "We are good to go"
            
            # ====== Install CCM Website (IIS front-end)
            Write-Host "Install CCM Website (IIS front-end)"
            Install-WindowsFeature Web-Server,Web-WebSockets,Web-Asp-Net45,Web-Windows-Auth -IncludeManagementTools

            Write-Host "Install dotnet-aspnetcoremodule-v2, dotnet-8.0-runtime and dotnet-8.0-aspnetruntime"
            choco install dotnet-aspnetcoremodule-v2 -y --source="$($NexusNuGetUrl)"
            choco install dotnet-8.0-runtime -y --source="$($NexusNuGetUrl)"
            choco install dotnet-8.0-aspnetruntime -y --source="$($NexusNuGetUrl)"

            Write-Host "Install chocolatey-management-web"
            choco install chocolatey-management-web -y --source="$($NexusNuGetUrl)" --package-parameters-sensitive="'/ConnectionString:$($ConnStr);User ID=$($DBUser);Password=$($DBUserPassword);'"
            #--package-parameters-sensitive="'/ConnectionString:Server=Localhost\SQLEXPRESS;Database=ChocolateyManagement;User ID=ChocoUser;Password=Ch0c0R0cks;'"
            #--package-parameters="'/ConnectionString:$ConnStr /CentralManagementServiceUrl:$CcmServiceUrl /CertificateThumbprint:$CertThumbprint /WebSiteUrl:$CcmWebUrl'"

            Import-Module WebAdministration
            Get-Website | Select-Object Name, State, PhysicalPath, Bindings
        }
        else{
            Write-Host -ForegroundColor Red "Prerequisite not met. Chocolatey Management Service not installed."
        }
    }
    else{
        Write-Host -ForegroundColor Red "Prerequisite not met. SQL Server not installed."
    }



}
else{
    Write-Host -ForegroundColor Red "Prerequisite not met. Can't read certificate thumbprint."
}
