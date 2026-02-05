<#
.SYNOPSIS
	Creates a self-signed TLS certificate for a Chocolatey for Business (C4B) / Chocolatey Central Management (CCM)
  	server and exports it as PFX (with private key) and CER (public cert) for client trust distribution.

.DESCRIPTION
	This script generates a self-signed server authentication certificate for the current host FQDN and short hostname
  and places it into Cert:\LocalMachine\My. It then exports:
    - PFX (includes private key) for server-side binding/use
    - CER (public certificate) for importing into client Trusted Root / Trusted People stores

  The script also imports:
    - The PFX into Cert:\LocalMachine\TrustedPeople
    - The CER into Cert:\LocalMachine\Root

  NOTE:
    - Self-signed certificates are recommended only for lab/testing environments.
      For production, use a certificate issued by a trusted internal PKI or public CA.
    - The resulting CER can be distributed via GPO, MDM, or a file share (e.g. \\server\certs)
      for client machines to trust the CCM service endpoint.


.PARAMETER Friendly
  Friendly name stored on the certificate. Default: "C4B Self-Signed TLS"

.PARAMETER Years
  Validity period (in years). Default: 1

.PARAMETER OutDir
  Output directory for exported files (PFX/CER). Default: D:\certs


.OUTPUTS
  - Writes certificate details (Subject, Thumbprint, NotAfter, FriendlyName) to the console
  - Creates:
      * <OutDir>\c4b-selfsigned.pfx
      * <OutDir>\c4b-selfsigned.cer


.REQUIREMENTS
  - Run as Administrator
  - PowerShell 5.1+ (New-SelfSignedCertificate available)
  

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
	# Create a 1-year self-signed cert and export to D:\certs
	.\CreateSelfSignedCert.ps1

	# Create a 3-year cert with a custom friendly name and output location
	.\CreateSelfSignedCert.ps1 -Friendly "CCM TLS (Lab)" -Years 3 -OutDir "E:\certs"
	
#>
param(
    [Parameter(Mandatory = $false)] [string] $Friendly = "C4B Self-Signed TLS",            # e.g. C4B Self-Signed TLS
    [Parameter(Mandatory = $false)] [int] $Years = 1,                                      # e.g. 1
    [Parameter(Mandatory = $false)] [string] $OutDir = "D:\certs"                          # e.g. D:\certs
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
    $ServerFqdn = "$($ServerName).$($domainName)"
}



# ---- CREATE CERT (in LocalMachine\My) ----
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$params = @{
  Type                  = 'Custom'
  Subject               = "CN=$($ServerFqdn)"
  DnsName               = @($ServerFqdn, $ServerName)
  KeyAlgorithm          = 'RSA'
  KeyLength             = 4096
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
Export-PfxCertificate -Cert $cert -FilePath "$($OutDir)\$($ServerFqdn)-selfsigned.pfx" -Password $pwd | Out-Null

# Export public cert only (CER) - for endpoints to trust
Export-Certificate -Cert $cert -FilePath "$($OutDir)\$($ServerFqdn)-selfsigned.cer" | Out-Null


Import-PfxCertificate -FilePath "$($OutDir)\$($ServerFqdn)-selfsigned.pfx" -CertStoreLocation "Cert:\LocalMachine\TrustedPeople" -Password $pwd | Out-Null

Import-Certificate -FilePath "$($OutDir)\$($ServerFqdn)-selfsigned.cer" -CertStoreLocation "Cert:\LocalMachine\Root" | Out-Null
