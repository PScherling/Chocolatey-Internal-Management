<#
.SYNOPSIS
  To install the Chocolatey Agent service, you need to install the chocolatey-agent package. 
  The Chocolatey Agent is only available for business edition customers to install from the licensed source 
  (customers trialling the business edition will be provided instructions on how to install).

.DESCRIPTION
  The Chocolatey Agent Service requires Log On As Service and Log On As Batch rights. 
  We attempt to set these rights on the user at the time of installation via Local Policy, 
  but if you have a restrictive Group Policy that will be applied to the system, 
  please ensure that the user account you are attempting to use (or ChocolateyLocalAdmin as the default) 
  has the correct permissions applied in your Group Policy.


.LINK
    https://community.chocolatey.org/packages/chocolatey
    https://docs.chocolatey.org/en-us/agent/setup/
    https://docs.chocolatey.org/en-us/central-management/setup/client/
	  https://github.com/PScherling
	
.NOTES
          FileName: Chocolatey-AgentSetup.ps1
          Solution: 
          Author: Patrick Scherling
          Contact: @Patrick Scherling
          Primary: @Patrick Scherling
          Created: 2026-01-30
          Modified: 2026-01-30

          Version - 0.0.1 - (2026-01-30) - Finalized functional version 1.

.REQUIREMENTS
  Chocolatey (chocolatey package)
  Chocolatey for Business (C4B) Edition
  Chocolatey Licensed Extension (chocolatey.extension package)
  Chocolatey Agent Service (chocolatey-agent package)


.EXAMPLE

    Requires administrative privileges.
#>

$ErrorActionPreference = 'Stop'

# Require admin
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
  throw "Run PowerShell as Administrator."
}

# Find FDQN for current machine
$ServerFqdn = [System.Net.Dns]::GetHostName()
$domainName = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().DomainName

if(-Not $ServerFqdn.endswith($domainName)) {
    $ServerFqdn += "." + $domainName
}

$CcmSvcUrl = "https://$($ServerFqdn):24020/ChocolateyManagementService"

if(choco){
  # Quick connectivity check (optional but useful)
  Write-Host "`nTesting connectivity to CCM service port..."
  if(-not (Test-NetConnection -ComputerName $ServerFqdn -Port 24020)){
    throw "CCM service not reachable."
  }
  else{
    Write-Host -ForegroundColor Green "We are good to go"
  }

  Write-Host "
==================================================================
Staring installation and configuration of Chocolatey Agent Service
CCM Service URL: $CcmSvcUrl"

  # Ensure licensed extension exists (required for C4B features)
  if (-not (choco list --local-only --exact chocolatey.extension --limit-output | Select-String '^chocolatey\.extension\|')) {
    throw "chocolatey.extension is not installed. Install it first from your internal licensed feed."
  }
  else{

    Write-Host -ForegroundColor Green "We are good to go"
    Write-Host "=================================================================="
    # Install/upgrade agent
    choco upgrade chocolatey-agent -y
    # Background service settings
    choco feature disable --name="showNonElevatedWarnings"
    choco feature enable --name="useBackgroundService"
    choco feature disable --name="useBackgroundServiceWithNonAdministratorsOnly"
    # Allow only what you want CCM deployments to execute
    choco config set --name="backgroundServiceAllowedCommands" --value "install,upgrade,uninstall,pin,sync"
    # Point client to CCM + enable CCM features
    choco config set --name="CentralManagementServiceUrl" --value "$($CcmSvcUrl)"
    choco feature enable --name="useChocolateyCentralManagement"
    # Requires Chocolatey Licensed Extension v2.1.0+, Chocolatey-Agent v0.10.0+, and Chocolatey Central Management v0.2.0+:
    choco feature enable --name="useChocolateyCentralManagementDeployments"

    # Ensure agent service is running
    $svc = Get-Service -Name chocolatey-agent -ErrorAction SilentlyContinue
    if (-not $svc) { 
      throw "Chocolatey Agent service not found after install. Check choco logs." 
    }
    else{

      if ($svc.Status -ne 'Running') {
        Start-Service -Name chocolatey-agent
      }

      Set-Service -Name chocolatey-agent -StartupType Automatic
      Write-Host -ForegroundColor Green "`nDone. Agent installed and configured."
    }
  }
}
else{
  Write-Host -ForegroundColor Red "Prerequisite not met. Chocolatey not installed."
}
