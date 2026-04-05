

# 🔐 cert-scan

### *TLS certificate inventory — IP ranges, host lists, one CSV.*

[PowerShell](https://github.com/PowerShell/PowerShell)
[Platform](https://www.microsoft.com/windows)
[TLS](https://en.wikipedia.org/wiki/Transport_Layer_Security)
[Export](#output-and-export)
[GitHub](https://github.com/amrmarey/cert-scan)
[Stars](https://github.com/amrmarey/cert-scan/stargazers)

  


**Pull cert metadata** (issuer, serial, days to expiry) **from each target** — **print a table** and **write a timestamped CSV** next to the script.

Built for inventories and expiry sweeps — not a substitute for a full PKI audit or pentest.

  


**[github.com/amrmarey/cert-scan](https://github.com/amrmarey/cert-scan)** · `git clone https://github.com/amrmarey/cert-scan.git`



  


> **TL;DR** — Put IPs or hostnames in a text file → run `**Scan-CertRange.ps1*`* → get `**cert-scan-*.csv**` plus a console summary.

  


## Jump to


|     | Section                                       |
| --- | --------------------------------------------- |
| 🎯  | [Overview](#overview)                         |
| 📋  | [Requirements](#requirements)                 |
| 🚀  | [Quick start](#quick-start)                   |
| ✨   | [Features](#features)                         |
| 🧰  | [CLI reference](#cli-reference)               |
| 📄  | [Input file](#input-file)                     |
| 📤  | [Output and export](#output-and-export)       |
| 🔒  | [Security and caveats](#security-and-caveats) |
| 🤝  | [Contributing](#contributing)                 |
| 📜  | [License](#license)                           |


  


---

## 🎯 Overview

```mermaid
flowchart LR
    A["📂 List or range"] --> B["Scan-CertRange.ps1"]
    B --> C["🖥️ Console table"]
    B --> D["📊 Timestamped CSV"]
```



Pick **one** mode per run:


| Mode         | When to use                                                                            |
| ------------ | -------------------------------------------------------------------------------------- |
| **📂 File**  | **IPs**, **IPv6**, **FQDNs** — one per line in `asset_list.txt` (or any path you pass) |
| **🔢 Range** | Contiguous **IPv4** only: `**-StartIP`** through `**-EndIP**`                          |


---

## 📋 Requirements


|         |                                                                                     |
| ------- | ----------------------------------------------------------------------------------- |
| Shell   | **Windows PowerShell 5.1** or **PowerShell 7+** (`pwsh`)                            |
| Network | Reachable targets on the `**-Port`** you choose (firewall / routing)                |
| Policy  | If scripts are blocked, use the **bypass** one-liner in [Quick start](#quick-start) |


---

## 🚀 Quick start

```powershell
cd <path-to>\cert-scan
```

**📂 File mode** *(recommended — IPs, IPv6, FQDNs)*

Edit `**asset_list.txt`**, then:

```powershell
.\Scan-CertRange.ps1 -IPListFile .\asset_list.txt
```



**🔢 Range mode** *(IPv4 sweep only)*

```powershell
.\Scan-CertRange.ps1 -StartIP 192.168.1.1 -EndIP 192.168.1.50
```



**🔓 Execution policy blocked?**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Scan-CertRange.ps1 -IPListFile .\asset_list.txt
```

On **PowerShell 7**, you can swap `powershell` for `pwsh`.



---

## ✨ Features




|     | Capability                                                       | ✓   |
| --- | ---------------------------------------------------------------- | --- |
| 🎯  | **Targets** — IPv4, IPv6, bracketed IPv6, DNS names from a list  | ✅   |
| 📡  | **Range mode** — single contiguous IPv4 stretch                  | ✅   |
| 🔌  | `**-Port`** — default `**443**`, any TCP port                    | ✅   |
| 📊  | **Auto CSV** — `cert-scan-yyyyMMdd-HHmmss.csv` beside the script | ✅   |
| 🧾  | `**-CsvPath`** — choose your own output path                     | ✅   |
| 🛡️ | Failures become rows with `**N/A**` and an `**Error**` column    | ✅   |




---

## 🧰 CLI reference


| Switch            | Required in | Default  | What it does                                 |
| ----------------- | ----------- | -------- | -------------------------------------------- |
| `**-StartIP**`    | Range       | —        | First IPv4 in range                          |
| `**-EndIP**`      | Range       | —        | Last IPv4 in range                           |
| `**-IPListFile**` | File        | —        | Path to target list                          |
| `**-Port**`       | —           | `443`    | TCP port                                     |
| `**-Timeout**`    | —           | `3000`   | Connect wait (**milliseconds**)              |
| `**-CsvPath`**    | —           | *(auto)* | Explicit CSV path; omit for timestamped file |


> Use **either** `**-StartIP*`* + `**-EndIP**` **or** `**-IPListFile`** — not both.

---

## 📄 Input file

`**asset_list.txt**` (or any path you pass to `**-IPListFile**`):


| Rule      |                                      |
| --------- | ------------------------------------ |
| Lines     | **One** IP or hostname per line      |
| Blank     | Ignored                              |
| `#`       | Comment to end of line               |
| Bad lines | **Warning** in console, line skipped |


```text
# Example
192.168.1.10
192.168.1.11
www.example.com
[2001:db8::80]
```

---

## 📤 Output and export


| Channel     | What you get                                                                                                                                                                                     |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Console** | Columns: `Asset_IP_Add`, `Cert_Issuer`, `Serial_Number`, `Days_Remaining`, `Error`                                                                                                               |
| **CSV**     | UTF-8, no type row (`Export-Csv -NoTypeInformation`); run ends with `CSV: <full path>`. `**Serial_Number`** is written as `**="…"**` so **Excel** shows full decimals (not scientific notation). |


**Custom path:**

```powershell
.\Scan-CertRange.ps1 -IPListFile .\asset_list.txt -CsvPath .\reports\last-scan.csv
```

---

## 🔒 Security and caveats

> [!WARNING]  
> The script **accepts any server certificate** (custom validation callback). Run only against **systems and networks you own or are explicitly authorized to test.**


| Topic             | Notes                                                                             |
| ----------------- | --------------------------------------------------------------------------------- |
| ⏱️ **Runtime**    | Large ranges multiply `**Timeout`** — plan wall-clock time                        |
| 🔀 **Inspection** | Corporate AV / proxies may replace certs; issuer may be **local**, not the origin |
| 🌐 **SNI**        | Hostnames in the list are used for **TLS SNI** — matches typical browser behavior |


---

## 🤝 Contributing

**Maintainer:** Amr Marey · **[amr.marey@msn.com](mailto:amr.marey@msn.com)**


|            |                                                                            |
| ---------- | -------------------------------------------------------------------------- |
| **Repo**   | **[github.com/amrmarey/cert-scan](https://github.com/amrmarey/cert-scan)** |
| **Issues** | **[Open an issue](https://github.com/amrmarey/cert-scan/issues)**          |
| **Clone**  | `git clone https://github.com/amrmarey/cert-scan.git`                      |


Pull requests are welcome — especially docs, edge cases, and safer defaults (without breaking simple “inventory mode”).

**Self-check:** run `**.\Validate-CertScan.ps1`** from the repo folder. It asserts that `**Serial_Number**` matches an independent TLS fetch (hex parse equals little-endian byte math), checks **CSV** columns, and verifies the **N/A + Error** shape when a connection fails.

---

## 📜 License

Use and adapt for your organization **as needed**. **No warranty** implied.

---



  


### *Scan the fleet. Ship the spreadsheet.*

**Made for operators who want answers in a spreadsheet — fast.**

Not another pane to babysit — a **CSV you can filter, pivot, and attach to a ticket.**

  



| 🔐                | 📊                     | ⚡                            |
| ----------------- | ---------------------- | ---------------------------- |
| **TLS** inventory | **CSV** out of the box | **One** `.ps1`, no installer |


  


`**[amrmarey/cert-scan](https://github.com/amrmarey/cert-scan)`**

Clone · aim at targets · export · done.

  


