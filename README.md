# Taitaja2026 - Active Directory Automation Suite

**SECURITY WARNING: INTENTIONALLY CREATION TOOL**

This project is designed to deploy a **Compromised-by-Design** Active Directory environment for cyber security training and red teaming practice.

**DO NOT** run these scripts in a production environment or on a network connected to production systems. The resulting domain contains intentional misconfigurations, weak passwords, and well known vulnerabilities.

---

## Overview

The suite automates the entire lifecycle of a Domain Controller deployment. It starts from a fresh Windows Server installation and results in a fully populated domain containing:
*   **Users & Groups**: Randomly generated identities with realistic metadata.
*   **Organizational Units**: A logical hierarchy (Users, Computers, Groups, Admins).
*   **Group Policies**: A mix of standard corporate policies and insecure configurations.
*   **Vulnerabilities**: Pre-baked attack paths including Kerberoasting, AS-REP Roasting, PrintNightmare, SMBv1, and more.
*   **SSH Infrastructure**: Automated installation of OpenSSH Server (optimized for WS2016) and planting of private SSH keys in user profiles.
*   **RDP Pivot Point**: Explicitly configured RDP access for specific user groups to facilitate movement between isolated networks.
*   **User Profile Initialization**: Automatic creation of local user profiles for special accounts using the Win32 API.
*   **Adversary Emulation**: Simulates a post-compromise state with a backdoor account and a persistent C2 beaconing task.

## Prerequisites

*   **OS**: Windows Server 2016, Windows Server 2019 or Windows Server 2022 (Standard or Datacenter).
    *   *Note: OpenSSH automated installation is currently optimized for Windows Server 2016.*
*   **Network**: A **Static IP Address** is highly recommended before starting.
*   **Privileges**: Local Administrator rights.
*   **Internet (Optional)**: Required if you want the script to configure a specific DNS forwarder (1.1.1.1), but the script works fully offline.

## Installation Guide

### 1. Prepare the Server
1.  Install a fresh copy of Windows Server.
2.  **Turn OFF** updates using `sconfig`.
3.  **Set a Static IP address**.
4.  **Rename the computer** to your desired DC name (e.g., `DC01`).
5.  Restart the server.

### 2. Deployment
1.  Copy the entire `Taitaja2026` folder to the server (e.g., `C:\Taitaja2026`).
2.  Open **PowerShell as Administrator**.
3.  Navigate to the `Scripts` directory:
    ```powershell
    cd C:\Taitaja2026\Scripts
    ```
4.  Run the installer:
    ```powershell
    .\installAD.ps1
    ```
5.  **Follow the Prompts**:
    *   Enter the desired **Domain Name** (e.g., `vuln.local`, `test.xyz`, `demo.local`).
    *   Enter a **Safe Mode Administrator Password**, it can be the same password used for the Administrator account.
    *   **[!] IMPORTANT**: After you enter the Password, do not interact with the terminal until the first reboot.

### 3. The Process
1.  **Stage 1**: The script installs AD DS and promotes the server. **The server will reboot automatically.**
2.  **Stage 2**: Log back in as `DOMAIN\Administrator`. The script will automatically resume (via Scheduled Task).
3.  **Completion**:
    *   DNS, Users, OUs, and GPOs are configured.
    *   Vulnerabilities are injected, and additional software (OpenSSH) is installed.
    *   **Cleanup**: The installation files will try to automatically delete themselves to leave no trace. **The script will inform if this fails.**
    *   **Final Reboot**: The server performs one last reboot to finalize all changes.

## Project Structure

```text
Taitaja2026/
├── Scripts/
│   ├── installAD.ps1                   # Main orchestrator (Reboot persistence)
│   ├── CreateUsersAndGroupsList.ps1    # JSON generation from source text
│   ├── GenerateIdentities.ps1          # User/Group/Computer/Special User creation
│   ├── CreateOU.ps1                    # OU structure & object moving
│   ├── GPOCreation.ps1                 # GPO deployment (Standard & Flawed)
│   ├── Malicious.ps1                   # Backdoors & C2 tasks
│   ├── Vulnerabilities.ps1             # AD-specific flaws (Roasting, etc.)
│   ├── InstallAPPs.ps1                 # Installs OpenSSH and enables RDP
│   ├── CreateSpecialUserProfiles.ps1   # Creates user profiles and plants SSH keys
│   ├── Data/                           # Source data files (JSON, TXT, XML)
│   └── Software/                       # Offline software binaries (OpenSSH)
├── FLAWS.md                            # Documentation of intentional vulnerabilities
└── README.md                           # This file
```

## Intentional Flaws & Scenario Features

For a detailed list of vulnerabilities and how to exploit them, see [FLAWS.md](FLAWS.md).

Key flaws and features include:
*   **Weak Passwords**: Domain-wide complexity disabled.
*   **Kerberoasting**: Service accounts with SPNs and weak passwords.
*   **AS-REP Roasting**: Users with pre-auth disabled.
*   **PrintNightmare**: Insecure "Point and Print" restrictions via GPO.
*   **Local Admin Abuse**: "Domain Users" added to Local Admins via GPO.
*   **SSH Key Exposure**: Private SSH keys planted in user profiles (Scenario Feature).
*   **RDP Pivot Points**: "Linux Users" granted RDP access to Domain Controllers (Scenario Feature).
*   **Legacy Protocols**: SMBv1 and WDigest enabled.

## Troubleshooting

*   **Execution Policy**: If scripts fail to run, ensure you can execute scripts: `Set-ExecutionPolicy Bypass -Scope Process`.
*   **Progress Bar Overlap**: If the console looks messy during DNS setup, this is visual only and does not affect the installation.
*   **Installation Breaks**: Interacting with the PowerShell window during Stage 1 can break the AD promotion. Avoid using the mouse or keyboard after starting.

---
**Author**: dlirao
