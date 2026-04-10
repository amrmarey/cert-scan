param(
    [Parameter(Mandatory=$true)]
    [string]$IPListFile,

    [int]$Timeout = 3000,

    [string]$CsvPath = ""
)

# ===============================
# Parse Asset
# ===============================
function Parse-Asset {
    param([string]$line)

    $line = $line.Trim()

    if ($line -match '^\s*$' -or $line.StartsWith("#")) {
        return $null
    }

    if ($line -match '^(.+?):(\d+)$') {
        return @{
            Address = $matches[1]
            Port = [int]$matches[2]
        }
    }

    return @{
        Address = $line
        Port = 443
    }
}

# ===============================
# Convert Serial to Decimal
# ===============================
function Convert-SerialToDecimal {
    param([byte[]]$bytes)

    $reversed = $bytes.Clone()
    [array]::Reverse($reversed)

    return [System.Numerics.BigInteger]::new($reversed)
}

# ===============================
# Get Cert Info
# ===============================
function Get-CertInfo {
    param(
        [string]$Address,
        [int]$Port
    )

    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $async = $tcp.BeginConnect($Address, $Port, $null, $null)

        if (-not $async.AsyncWaitHandle.WaitOne($Timeout)) {
            throw "Connection timeout"
        }

        $tcp.EndConnect($async)

        $sslStream = New-Object System.Net.Security.SslStream(
            $tcp.GetStream(),
            $false,
            ({ $true })
        )

        $sslStream.AuthenticateAsClient($Address)

        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $sslStream.RemoteCertificate

        $serialDecimal = Convert-SerialToDecimal $cert.GetSerialNumber()

        return @{
            Asset_IP_Add = $Address
            Port = $Port
            HTTPS = "Yes"
            Serial_Number = $serialDecimal.ToString()
            Error = ""
        }

    } catch {
        return @{
            Asset_IP_Add = $Address
            Port = $Port
            HTTPS = "No"
            Serial_Number = "N/A"
            Error = $_.Exception.Message
        }
    }
}

# ===============================
# Main
# ===============================
$results = @()

Get-Content $IPListFile | ForEach-Object {
    $parsed = Parse-Asset $_

    if ($null -eq $parsed) {
        return
    }

    $result = Get-CertInfo -Address $parsed.Address -Port $parsed.Port
    $results += New-Object PSObject -Property $result
}

# ===============================
# Output
# ===============================
$results | Format-Table -AutoSize

if ([string]::IsNullOrEmpty($CsvPath)) {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $CsvPath = ".\cert-scan-$timestamp.csv"
}

$results | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8

Write-Host "CSV exported to: $CsvPath"