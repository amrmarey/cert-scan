<div align="center">

# 🔐 cert-scan

### *TLS certificate inventory — IP ranges, host lists, one CSV.*

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207+-5391FE?style=for-the-badge&logo=powershell&logoColor=white)](https://github.com/PowerShell/PowerShell)
[![Platform](https://img.shields.io/badge/platform-Windows-0078D6?style=for-the-badge&logo=windows&logoColor=white)](https://www.microsoft.com/windows)
[![TLS](https://img.shields.io/badge/transport-TLS%2FSSL-6366F1?style=for-the-badge&logoColor=white)](https://en.wikipedia.org/wiki/Transport_Layer_Security)
[![Export](https://img.shields.io/badge/export-CSV-217346?style=for-the-badge&logo=microsoftexcel&logoColor=white)](#output-and-export)
[![GitHub repo](https://img.shields.io/badge/GitHub-amrmarey%2Fcert--scan-181717?style=for-the-badge&logo=github)](https://github.com/amrmarey/cert-scan)

<br />

**Pull cert metadata** (issuer, serial, days left) **from every target** — then **drop results to disk** for spreadsheets or dashboards.

<sub>Built for quick inventories & expiry checks — not a full PKI / pen-test story.</sub>

<br />

[**github.com/amrmarey/cert-scan**](https://github.com/amrmarey/cert-scan) · `git clone https://github.com/amrmarey/cert-scan.git`

</div>

<br />

---

<br />

## Jump to

|  | Section |
|--|---------|
| 🎯 | [Overview](#overview) |
| 📋 | [Requirements](#requirements) |
| 🚀 | [Quick start](#quick-start) |
| ✨ | [Features](#features) |
| 🧰 | [CLI reference](#cli-reference) |
| 📄 | [Input file](#input-file) |
| 📤 | [Output and export](#output-and-export) |
| 🔒 | [Security and caveats](#security-and-caveats) |
| 🤝 | [Contributing](#contributing) |
| 📜 | [License](#license) |

<br />

---

<br />

## 🎯 Overview

```text
┌─────────────┐     ┌──────────────────┐     ┌─────────────┐
│ asset list  │ ──▶ │  Scan-CertRange  │ ──▶ │ Console +   │
│ or IP range │     │  (.ps1)          │     │ timestamped │
└─────────────┘     └──────────────────┘     │ CSV         │
                                             └─────────────┘
```

Pick **one** mode per run:

| Mode | When to use |
|------|----------------|
| **📂 File** | Mixed **IPs**, **IPv6**, and **FQDNs** from `asset_ip_add.txt` (or any path) |
| **🔢 Range** | Sweep a contiguous **IPv4** block (**`-StartIP`** … **`-EndIP`**) |

---

## 📋 Requirements

- **Windows PowerShell 5.1** *or* **PowerShell 7+**
- **Network** path to targets (firewall / routing allowing the chosen **`-Port`**)
- If scripts are blocked: **execution policy** bypass for this file only (see [Quick start](#quick-start))

---

## 🚀 Quick start

```powershell
cd <path-to>\cert-scan
```

<details open>
<summary><strong>📂 File mode</strong> <em>(recommended)</em></summary>

Edit **`asset_ip_add.txt`**, then:

```powershell
.\Scan-CertRange.ps1 -IPListFile .\asset_ip_add.txt
```

</details>

<details>
<summary><strong>🔢 Range mode</strong> <em>(IPv4 only)</em></summary>

```powershell
.\Scan-CertRange.ps1 -StartIP 192.168.1.1 -EndIP 192.168.1.50
```

</details>

<details>
<summary><strong>🔓 Execution policy blocked?</strong></summary>

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Scan-CertRange.ps1 -IPListFile .\asset_ip_add.txt
```

</details>

---

## ✨ Features

<div align="center">

| | Capability | ✓ |
|--|------------|---|
| 🎯 | **Targets** — IPv4, IPv6, bracketed IPv6, DNS names from a list | ✅ |
| 📡 | **Range mode** — single IPv4 stretch | ✅ |
| 🔌 | **`-Port`** — default `443`, any TCP port | ✅ |
| 📊 | **Auto CSV** — `cert-scan-YYYYMMDD-HHMMss.csv` beside the script | ✅ |
| 🧾 | **`-CsvPath`** — pin your own output file | ✅ |
| 🛡️ | Failed connects → row with **`N/A`** + **`Error`** | ✅ |

</div>

---

## 🧰 CLI reference

| Switch | Required in | Default | What it does |
|--------|-------------|---------|----------------|
| **`-StartIP`** | Range | — | First IPv4 in range |
| **`-EndIP`** | Range | — | Last IPv4 in range |
| **`-IPListFile`** | File | — | Path to target list |
| **`-Port`** | — | `443` | TCP port |
| **`-Timeout`** | — | `3000` | Connect timeout (**ms**) |
| **`-CsvPath`** | — | *(auto)* | Explicit CSV path |

> **Either** pass **`-StartIP`** + **`-EndIP`** **or** **`-IPListFile`** — not both.

---

## 📄 Input file

**`asset_ip_add.txt`** (or any list you pass):

- **One** IP or hostname per line  
- **Blank** lines skipped  
- **`#`** starts a comment  
- **Garbage** lines → **warning** + skip  

```text
# ── Example ─────────────────────
192.168.1.10
192.168.1.11
www.example.com
[2001:db8::80]
```

---

## 📤 Output and export

| Channel | |
|--------|---|
| **🖥️ Console** | `Asset_IP_Add`, `Cert_Issuer`, `Serial_Number`, `Days_Remaining`, `Error` |
| **📁 CSV** | UTF-8; **`-NoTypeInformation`**; script echoes `CSV: <path>` |

**Custom CSV path:**

```powershell
.\Scan-CertRange.ps1 -IPListFile .\asset_ip_add.txt -CsvPath .\reports\last-scan.csv
```

---

## 🔒 Security and caveats

> [!WARNING]  
> The script **accepts any presented certificate** (custom validation callback). Use only on **networks and systems you own or are explicitly authorized to test** — not on arbitrary internet hosts without permission.

| Topic | Notes |
|--------|--------|
| ⏱️ **Time** | Big ranges × **`-Timeout`** = long runs |
| 🔀 **TLS inspection** | AV / proxies may show a **local issuer** instead of the real server cert |
| 🌐 **SNI** | Hostname in the file is used for **TLS SNI** — correct for normal FQDN checks |

---

## 🤝 Contributing

Maintained by **Amr Marey**. Contributions, issues, and pull requests are welcome on the public repo:

**[https://github.com/amrmarey/cert-scan](https://github.com/amrmarey/cert-scan)**

- **Contact:** [amr.marey@msn.com](mailto:amr.marey@msn.com)  
- **Clone:** `git clone https://github.com/amrmarey/cert-scan.git`

---

## 📜 License

Use and adapt for your organization **as needed**. **No warranty** implied.

---

<div align="center">

<br />

**Made for operators who want answers in a spreadsheet — fast.**

🔐 · 📊 · ⚡ · [`amrmarey/cert-scan`](https://github.com/amrmarey/cert-scan)

</div>
