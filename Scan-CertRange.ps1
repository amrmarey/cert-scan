#Requires -Version 5.1

<#
.SYNOPSIS
    TLS certificate inventory scanner — reads asset_list.txt, outputs CSV.
.PARAMETER IPListFile
    Path to target list. One IP or FQDN per line.
.PARAMETER Port
    Default TCP port (default: 443).
.PARAMETER Timeout
    Connection timeout in milliseconds (default: 3000).
.PARAMETER CsvPath
    Output CSV path; timestamped file next to script if omitted.
.EXAMPLE
    .\Scan-CertRange.ps1 -IPListFile .\asset_list.txt
.EXAMPLE
    .\Scan-CertRange.ps1 -IPListFile .\asset_list.txt -Port 8443 -CsvPath .\out.csv
#>
param(
    [Parameter(Mandatory)][string]$IPListFile,
    [int]   $Port    = 443,
    [int]   $Timeout = 3000,
    [string]$CsvPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
#  Helpers
# ---------------------------------------------------------------------------

function ConvertTo-Assets ([string]$Path, [int]$DefaultPort) {
    $list = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($raw in Get-Content $Path) {
        $line = ($raw -replace '#.*$', '').Trim()
        if (-not $line) { continue }
        # IPv6 bracket notation: [::1] or [::1]:8443
        if ($line -match '^\[([^\]]+)\](?::(\d+))?$') {
            $list.Add([pscustomobject]@{
                Address = $Matches[1]
                Port    = if ($Matches[2]) { [int]$Matches[2] } else { $DefaultPort }
            }); continue
        }
        # host:port (IPv4 or hostname)
        if ($line -match '^([^:]+):(\d+)$') {
            $list.Add([pscustomobject]@{ Address = $Matches[1]; Port = [int]$Matches[2] }); continue
        }
        $list.Add([pscustomobject]@{ Address = $line; Port = $DefaultPort })
    }
    return $list
}

function Get-TlsCertificate ([string]$Address, [int]$Port, [int]$TimeoutMs) {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $ssl = $null
    try {
        $ar = $tcp.BeginConnect($Address, $Port, $null, $null)
        if (-not $ar.AsyncWaitHandle.WaitOne($TimeoutMs)) {
            throw "Connection timed out after ${TimeoutMs}ms"
        }
        $tcp.EndConnect($ar)

        $noValidate = [System.Net.Security.RemoteCertificateValidationCallback]{ $true }
        $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false, $noValidate)
        $ssl.AuthenticateAsClient($Address)

        return [System.Security.Cryptography.X509Certificates.X509Certificate2]$ssl.RemoteCertificate
    }
    finally {
        if ($ssl) { $ssl.Dispose() }
        if ($tcp) { $tcp.Dispose() }
    }
}

function Get-CertSANs ([System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert) {
    $ext = $Cert.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.17' }
    if (-not $ext) { return '' }
    # Format(false) returns comma-separated entries, e.g. "DNS Name=github.com, DNS Name=www.github.com"
    return (
        ($ext.Format($false) -split ',\s*' | Where-Object { $_ }) |
        ForEach-Object {
            $_ -replace '^DNS Name=',    'DNS:'   `
               -replace '^IP Address=',  'IP:'    `
               -replace '^RFC822 Name=', 'email:' `
               -replace '^URL=',         'URI:'
        }
    ) -join '; '
}

function Get-SerialHex ([System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert) {
    # GetSerialNumber() returns bytes little-endian; reverse for big-endian (ASN.1 order)
    $bytes = $Cert.GetSerialNumber()
    [System.Array]::Reverse($bytes)
    return ($bytes | ForEach-Object { $_.ToString('X2') }) -join ''
}

function ConvertTo-DecimalSerial ([string]$HexSerial) {
    [System.Numerics.BigInteger]::Parse(
        '0' + $HexSerial,
        [System.Globalization.NumberStyles]::HexNumber
    ).ToString()
}

function Get-ExpiryStatus ([int]$Days) {
    if ($Days -lt 0)      { 'Expired'  }
    elseif ($Days -lt 30) { 'Critical' }
    elseif ($Days -lt 90) { 'Warning'  }
    else                  { 'Healthy'  }
}

# ---------------------------------------------------------------------------
#  Main
# ---------------------------------------------------------------------------

if (-not (Test-Path $IPListFile)) {
    Write-Error "Asset list not found: $IPListFile"
    exit 1
}

if (-not $CsvPath) {
    $ts      = Get-Date -Format 'yyyyMMdd_HHmmss'
    $CsvPath = Join-Path (Split-Path -Parent $PSCommandPath) "cert_scan_$ts.csv"
}

$assets  = ConvertTo-Assets -Path $IPListFile -DefaultPort $Port
$results = [System.Collections.Generic.List[pscustomobject]]::new()

Write-Host ("`n{0,-32} {1,-6} {2,-10} {3,6}  {4}" -f 'Asset', 'Port', 'Status', 'Days', 'Expiry')
Write-Host ('-' * 70)

foreach ($asset in $assets) {
    $row = [ordered]@{
        Asset_IP_Add      = $asset.Address
        Port              = $asset.Port
        HTTPS             = 'No'
        Cert_Issuer       = 'N/A'
        Serial_Number     = 'N/A'
        Serial_Hex        = 'N/A'
        Subject_Alt_Names = 'N/A'
        Days_Remaining    = 'N/A'
        Expiry_Date       = 'N/A'
        Expiry_Status     = 'N/A'
        Error             = ''
    }

    try {
        $cert = Get-TlsCertificate -Address $asset.Address -Port $asset.Port -TimeoutMs $Timeout
        $days = [int][math]::Floor(($cert.NotAfter.ToUniversalTime() - [datetime]::UtcNow).TotalDays)
        $hex  = Get-SerialHex -Cert $cert

        $row.HTTPS             = 'Yes'
        $row.Cert_Issuer       = $cert.Issuer
        $row.Serial_Number     = ConvertTo-DecimalSerial $hex
        $row.Serial_Hex        = "0x$hex"
        $row.Subject_Alt_Names = Get-CertSANs -Cert $cert
        $row.Days_Remaining    = $days
        $row.Expiry_Date       = $cert.NotAfter.ToUniversalTime().ToString('yyyy-MM-dd HH:mm UTC')
        $row.Expiry_Status     = Get-ExpiryStatus $days

        $color = switch ($row.Expiry_Status) {
            'Expired'  { 'Red'    }
            'Critical' { 'Red'    }
            'Warning'  { 'Yellow' }
            default    { 'Green'  }
        }
        Write-Host ('{0,-32} {1,-6} {2,-10} {3,6}  {4}' -f
            $asset.Address, $asset.Port, $row.Expiry_Status, $days, $row.Expiry_Date
        ) -ForegroundColor $color
    }
    catch {
        $row.Error = $_.Exception.Message
        Write-Host ('{0,-32} {1,-6} {2}' -f $asset.Address, $asset.Port, 'FAILED') -ForegroundColor DarkGray
    }

    $results.Add([pscustomobject]$row)
}

Write-Host ''
$results | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
Write-Host "Scanned $($results.Count) asset(s). Report: $CsvPath`n"
