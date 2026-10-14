<#
.SYNOPSIS
    Injects specific Active Directory vulnerabilities through service accounts and account attributes.

.DESCRIPTION
    Automates the creation of accounts vulnerable to modern AD attack techniques.
    - Kerberoasting: Creates a service account with an SPN and a weak password.
    - AS-REP Roasting: Creates a user account with Kerberos pre-authentication disabled.
#>

function Enable-Kerberoasting {
    <#
    .SYNOPSIS
        Creates a vulnerable service account for Kerberoasting.
    .DESCRIPTION
        Creates a user account with a Service Principal Name (SPN) and a weak password.
        This allows attackers to request a TGS ticket for the service and crack the password offline.
    #>
    [CmdletBinding()]
    param (
        [string]$DomainName = (Get-ADDomain).DNSRoot
    )

    $VulnUser = "SQLService"
    $VulnPass = "kilpikonna"
    $SPN = "SQLService/db.$DomainName"

    try {
        Write-Host "Creating the Service Account for Kerberoasting vulnerability..." -ForegroundColor Yellow
        
        # Create the user if it doesn't exist
        if (-not (Get-ADUser -Filter {SamAccountName -eq $VulnUser} -ErrorAction SilentlyContinue)) {
            New-ADUser -Name $VulnUser `
                -SamAccountName $VulnUser `
                -UserPrincipalName "$VulnUser@$DomainName" `
                -AccountPassword (ConvertTo-SecureString $VulnPass -AsPlainText -Force) `
                -Enabled $true `
                -ChangePasswordAtLogon $false `
                -DisplayName "SQL Service Account" `
                -Description "Service Account for SQL" `
                -PassThru | Out-Null
            Write-Host "  [+] Created user: $VulnUser" -ForegroundColor Green
        } else {
            Write-Host "  [*] User $VulnUser already exists." -ForegroundColor Gray
        }

        # Set the SPN
        Set-ADUser -Identity $VulnUser -ServicePrincipalNames @{Add=$SPN} -ErrorAction Stop
        Write-Host "  [+] Assigned SPN: $SPN" -ForegroundColor Green
        Write-Host "  [!] Vulnerability Active: Kerberoasting is now possible on $VulnUser" -ForegroundColor Red
        Write-Host ""

    } catch {
        Write-Error "Failed to implement Kerberoasting: $_"
    }
}

function Enable-ASREPRoasting {
    <#
    .SYNOPSIS
        Creates a user vulnerable to AS-REP Roasting.
    .DESCRIPTION
        Creates a user account with 'Do not require Kerberos preauthentication' enabled.
        This allows attackers to request an AS-REP for the user and crack the password hash offline.
    #>
    [CmdletBinding()]
    param (
        [string]$DomainName = (Get-ADDomain).DNSRoot
    )

    $VulnUser = "PrintUser"
    $VulnPass = "salasana123"
    
    try {
        Write-Host "Injecting AS-REP Roasting vulnerability..." -ForegroundColor Yellow
        
        # Create the user if it doesn't exist
        if (-not (Get-ADUser -Filter {SamAccountName -eq $VulnUser} -ErrorAction SilentlyContinue)) {
            New-ADUser -Name $VulnUser `
                -SamAccountName $VulnUser `
                -UserPrincipalName "$VulnUser@$DomainName" `
                -AccountPassword (ConvertTo-SecureString $VulnPass -AsPlainText -Force) `
                -Enabled $true `
                -ChangePasswordAtLogon $false `
                -DisplayName "Print User" `
                -Description "User for the prints to work" `
                -PassThru | Out-Null
            Write-Host "  [+] Created user: $VulnUser" -ForegroundColor Green
        }

        # Disable Kerberos Pre-authentication (UF_DONT_REQUIRE_PREAUTH = 0x400000)
        Set-ADAccountControl -Identity $VulnUser -DoesNotRequirePreAuth $true -ErrorAction Stop
        Write-Host "  [+] Disabled Kerberos Pre-authentication for $VulnUser" -ForegroundColor Green
        Write-Host "  [!] Vulnerability Active: AS-REP Roasting is now possible on $VulnUser" -ForegroundColor Red
        Write-Host ""

    } catch {
        Write-Error "Failed to implement AS-REP Roasting: $_"
    }
}

# Execution Block
$Domain = (Get-ADDomain).DNSRoot

Enable-Kerberoasting -DomainName $Domain
Enable-ASREPRoasting -DomainName $Domain
