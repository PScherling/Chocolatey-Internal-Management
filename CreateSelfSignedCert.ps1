# ---- SETTINGS ----
$Fqdn      = "psc-c4bsrv.local"
$ShortName = "psc-c4bsrv"
$Friendly  = "C4B Self-Signed TLS"
$Years     = 1
$OutDir    = "D:\certs"

# ---- CREATE CERT (in LocalMachine\My) ----
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$params = @{
  Type                  = 'Custom'
  Subject               = "CN=$($Fqdn)"
  DnsName               = @($Fqdn, $ShortName)
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
