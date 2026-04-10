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
# Expiry Classification
# ===============================
function Get-ExpiryStatus {
    param([int]$days)

    if ($days -lt 0) { return "Expired" }
    elseif ($days -lt 30) { return "Critical" }
    elseif ($days -lt 90) { return "Warning" }
    else { return "Healthy" }
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

        # HTTPS enforced
        $sslStream.AuthenticateAsClient($Address)

        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $sslStream.RemoteCertificate

        # Serial (decimal)
        $serialDecimal = Convert-SerialToDecimal $cert.GetSerialNumber()
        $serialFormatted = '="' + $serialDecimal.ToString() + '"'

        # Issuer
        $issuer = $cert.Issuer

        # Expiry
        $daysRemaining = (New-TimeSpan -Start (Get-Date) -End $cert.NotAfter).Days
        $expiryStatus = Get-ExpiryStatus $daysRemaining

        return @{
            Asset_IP_Add   = $Address
            Port           = $Port
            HTTPS          = "Yes"
            Cert_Issuer    = $issuer
            Serial_Number  = $serialFormatted
            Days_Remaining = $daysRemaining
            Expiry_Date    = $cert.NotAfter
            Expiry_Status  = $expiryStatus
            Error          = ""
        }

    } catch {
        return @{
            Asset_IP_Add   = $Address
            Port           = $Port
            HTTPS          = "No"
            Cert_Issuer    = "N/A"
            Serial_Number  = "N/A"
            Days_Remaining = "N/A"
            Expiry_Date    = "N/A"
            Expiry_Status  = "N/A"
            Error          = $_.Exception.Message
        }
    }
}

# ===============================
# Main Execution
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
# Console Output (Ordered)
# ===============================
$results | Select-Object `
    Asset_IP_Add,
    Port,
    HTTPS,
    Cert_Issuer,
    Serial_Number,
    Days_Remaining,
    Expiry_Status,
    Error | Format-Table -AutoSize

# ===============================
# CSV Output
# ===============================
if ([string]::IsNullOrEmpty($CsvPath)) {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $CsvPath = ".\cert-scan-$timestamp.csv"
}

$results | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8

Write-Host "CSV exported to: $CsvPath"