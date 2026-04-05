param(
    [Parameter(Mandatory, ParameterSetName = 'Range')]
    [string]$StartIP,
    [Parameter(Mandatory, ParameterSetName = 'Range')]
    [string]$EndIP,

    [Parameter(Mandatory, ParameterSetName = 'File')]
    [ValidateScript({ Test-Path -LiteralPath $_ })]
    [string]$IPListFile,

    [int]$Port = 443,
    [int]$Timeout = 3000,

    [Parameter()]
    [string]$CsvPath
)

function Get-IPRange {
    param($StartIP, $EndIP)

    $start = [System.Net.IPAddress]::Parse($StartIP).GetAddressBytes()
    $end   = [System.Net.IPAddress]::Parse($EndIP).GetAddressBytes()

    if ($start.Length -ne 4 -or $end.Length -ne 4) {
        throw 'Only IPv4 ranges are supported.'
    }

    [Array]::Reverse($start)
    [Array]::Reverse($end)

    $startInt = [BitConverter]::ToUInt32($start, 0)
    $endInt   = [BitConverter]::ToUInt32($end, 0)

    if ($startInt -gt $endInt) {
        throw 'StartIP must be less than or equal to EndIP.'
    }

    for ($i = $startInt; $i -le $endInt; $i++) {
        $bytes = [BitConverter]::GetBytes($i)
        [Array]::Reverse($bytes)
        [System.Net.IPAddress]::new($bytes).ToString()
    }
}

function Get-TargetListFromFile {
    param([string]$Path)

    Get-Content -LiteralPath $Path | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith('#')) { return }

        $token = $line
        if ($token -match '^\[(.+)\]$') {
            $token = $Matches[1]
        }

        $addr = $null
        if ([System.Net.IPAddress]::TryParse($token, [ref]$addr)) {
            $ipStr = $addr.IPAddressToString
            [pscustomobject]@{
                AssetLabel  = $ipStr
                ConnectHost = $ipStr
                TlsHostName = $ipStr
            }
            return
        }

        if ([System.Uri]::CheckHostName($line) -eq [System.UriHostNameType]::Dns) {
            [pscustomobject]@{
                AssetLabel  = $line
                ConnectHost = $line
                TlsHostName = $line
            }
            return
        }

        Write-Warning "Skipping invalid target (not an IP or DNS hostname): $line"
    }
}

function Get-CertificateSerialDecimal {
    # SerialNumber = big-endian hex (openssl-style). Fallback: GetSerialNumber() LE bytes.
    param([System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert)

    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $hex = ($Cert.SerialNumber -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($hex)) {
        return '0'
    }
    if ($hex.Length % 2 -eq 1) {
        $hex = '0' + $hex
    }

    try {
        return [System.Numerics.BigInteger]::Parse(
            $hex,
            [System.Globalization.NumberStyles]::AllowHexSpecifier,
            $inv
        ).ToString($inv)
    }
    catch {
        $bytes = $Cert.GetSerialNumber()
        if ($bytes.Length -eq 0) {
            return '0'
        }
        if ($bytes[$bytes.Length - 1] -band 0x80) {
            $tmp = New-Object byte[] ($bytes.Length + 1)
            [Array]::Copy($bytes, $tmp, $bytes.Length)
            $bytes = $tmp
        }
        return ([System.Numerics.BigInteger]::new($bytes)).ToString($inv)
    }
}

function Get-CertInfo {
    param(
        [string]$AssetLabel,
        [string]$ConnectHost,
        [string]$TlsHostName,
        [int]$Port,
        [int]$Timeout
    )

    $tcp = $null
    $ssl = $null
    try {
        $tcp = [System.Net.Sockets.TcpClient]::new()
        $async = $tcp.BeginConnect($ConnectHost, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($Timeout)) {
            throw [System.TimeoutException]::new('Connection timed out.')
        }
        $tcp.EndConnect($async)

        $callback = [System.Net.Security.RemoteCertificateValidationCallback] {
            param($sender, $certificate, $chain, $sslPolicyErrors)
            return $true
        }
        $ssl = [System.Net.Security.SslStream]::new($tcp.GetStream(), $false, $callback)
        $ssl.AuthenticateAsClient($TlsHostName)

        $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($ssl.RemoteCertificate)

        return [pscustomobject]@{
            Asset_IP_Add   = $AssetLabel
            Cert_Issuer    = $cert.Issuer
            Serial_Number  = Get-CertificateSerialDecimal -Cert $cert
            Days_Remaining = [int](New-TimeSpan -Start (Get-Date) -End $cert.NotAfter).Days
            Error          = ''
        }
    }
    catch {
        return [pscustomobject]@{
            Asset_IP_Add   = $AssetLabel
            Cert_Issuer    = 'N/A'
            Serial_Number  = 'N/A'
            Days_Remaining = 'N/A'
            Error          = $_.Exception.Message
        }
    }
    finally {
        if ($ssl) { $ssl.Dispose() }
        if ($tcp) { $tcp.Close() }
    }
}

$targets = if ($PSCmdlet.ParameterSetName -eq 'File') {
    @(Get-TargetListFromFile -Path $IPListFile)
}
else {
    foreach ($ip in Get-IPRange $StartIP $EndIP) {
        [pscustomobject]@{
            AssetLabel  = $ip
            ConnectHost = $ip
            TlsHostName = $ip
        }
    }
}

$results = foreach ($t in $targets) {
    Get-CertInfo -AssetLabel $t.AssetLabel -ConnectHost $t.ConnectHost -TlsHostName $t.TlsHostName -Port $Port -Timeout $Timeout
}

# Excel treats long digit strings as numbers → scientific notation. Emit ="digits" so the cell stays text.
function Format-SerialForExcelCsv {
    param([string]$Serial)
    if ($Serial -match '^\d+$') {
        return '="' + $Serial + '"'
    }
    return $Serial
}

$csvRows = foreach ($r in $results) {
    [pscustomobject]@{
        Asset_IP_Add   = $r.Asset_IP_Add
        Cert_Issuer    = $r.Cert_Issuer
        Serial_Number  = (Format-SerialForExcelCsv -Serial ([string]$r.Serial_Number))
        Days_Remaining = $r.Days_Remaining
        Error          = $r.Error
    }
}

$csvOut = if ($CsvPath) {
    $CsvPath
}
else {
    $dir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    Join-Path $dir ('cert-scan-{0:yyyyMMdd-HHmmss}.csv' -f (Get-Date))
}

$csvRows | Export-Csv -LiteralPath $csvOut -NoTypeInformation -Encoding utf8
Write-Host "CSV: $csvOut"

$results | Format-Table -AutoSize
