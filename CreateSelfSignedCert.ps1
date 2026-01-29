<#
.SYNOPSIS


.DESCRIPTION


.LINK
    
	https://github.com/PScherling
	
.NOTES
          FileName: CreateSelfSignedCert.ps1
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
    [Parameter][string]$Friendly = "C4B Self-Signed TLS",            # e.g. C4B Self-Signed TLS
    [Parameter][int]$Years = 1,                                      # e.g. 1
    [Parameter][string]$OutDir = "D:\certs"                          # e.g. D:\certs
)

$ErrorActionPreference = 'Stop'

# Require admin
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
  throw "Run PowerShell as Administrator."
}

# ====== YOUR ENV SETTINGS ======
# Find FDQN for current machine
$ServerName = [System.Net.Dns]::GetHostName()
$domainName = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().DomainName

if(-Not $ServerName.endswith($domainName)) {
    $ServerFqdn += "." + $domainName
}



# ---- CREATE CERT (in LocalMachine\My) ----
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$params = @{
  Type                  = 'Custom'
  Subject               = "CN=$($ServerFqdn)"
  DnsName               = @($ServerFqdn, $ServerName)
  KeyAlgorithm          = 'RSA'
  KeyLength             = 2048
  HashAlgorithm         = 'SHA256'
  KeyUsage              = @('DigitalSignature', 'KeyEncipherment')
  TextExtension         = @("2.5.29.37={text}1.3.6.1.5.5.7.3.1")      # EKU = Server Authentication
  KeyExportPolicy       = 'Exportable'
  CertStoreLocation     = "Cert:\LocalMachine\My"
  FriendlyName          = "$($Friendly)"
  NotAfter              = (Get-Date).AddYears($Years)
}

$cert = New-SelfSignedCertificate @params

$cert | Format-List Subject, Thumbprint, NotAfter, FriendlyName

$pwd = Read-Host "Enter a PFX password" -AsSecureString

# Export with private key (PFX)
Export-PfxCertificate -Cert $cert -FilePath "$($OutDir)\c4b-selfsigned.pfx" -Password $pwd | Out-Null

# Export public cert only (CER) - for endpoints to trust
Export-Certificate -Cert $cert -FilePath "$($OutDir)\c4b-selfsigned.cer" | Out-Null


Import-PfxCertificate -FilePath "$($OutDir)\c4b-selfsigned.pfx" -CertStoreLocation "Cert:\LocalMachine\TrustedPeople" -Password $pwd | Out-Null

Import-Certificate -FilePath "$($OutDir)\c4b-selfsigned.cer" -CertStoreLocation "Cert:\LocalMachine\Root" | Out-Null
