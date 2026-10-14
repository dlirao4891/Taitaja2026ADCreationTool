<#
.SYNOPSIS
    Primary orchestrator for the Taitaja2026 Active Directory deployment.

.DESCRIPTION
    This script automates the installation of AD DS and the promotion of the server to a Domain Controller.
    It uses a two-stage execution logic via Scheduled Tasks and Registry persistence (HKLM) to survive
    the mandatory reboot after promotion.
    
    Stage 1: Installs AD DS features and promotes the server to a Forest Root DC.
    Stage 2: (After Reboot) Configures DNS, OUs, Users, Groups, GPOs, and injects vulnerabilities.

.NOTES
    Requires: Administrator privileges, static IP, and pre-configured Server Name.
    The script assumes a fresh Windows Server installation.
#>

$RegPath = "HKLM:\SOFTWARE\ADAutomationSuite"
$ValueName = "ISRun"
$regkeyexists = Test-Path -Path $regPath
if ($regkeyexists) {
    #Check if registry entry named ADAutomationSuite exists
    $regentryexists = Get-ItemProperty -Path $regpath -Name $ValueName -ErrorAction SilentlyContinue
    if ($regentryexists) {
        # This is a continuation after reboot
        Write-Host "Continuing with the next part of the script..." -ForegroundColor Green
        Write-Host ""

        # Sets DNS server to Server's own IP and Quad-1, if internet is available
        Write-Host "Configuring DNS server settings..." -ForegroundColor Yellow
        Write-Host ""
        $ServerIP = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Ethernet").IPAddress
        
        $OldProgressPreference = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        
        $DNSTest = Test-Connection 1.1.1.1 -Count 1 -Quiet
        If ($DNSTest) {
            Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses ("$ServerIP","1.1.1.1") | Out-Null
            Write-Host "Set DNS server to $ServerIP and 1.1.1.1" -ForegroundColor Green
            Write-Host ""
        } else {
            Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses ("$ServerIP") | Out-Null
            Write-Host "Set DNS server to $ServerIP, it appears there is no internet connection." -ForegroundColor Green
            Write-Host ""
        }
        
        $ProgressPreference = $OldProgressPreference
        
        Write-Host "Waiting for services to stabilize..." -ForegroundColor Yellow
        start-sleep -s 20

        # Invoke other scripts to finalize the AD setup
        Write-Host "Creating users and groups..." -ForegroundColor Green
        & "$(Split-Path $MyInvocation.MyCommand.Path)/CreateUsersAndGroupsList.ps1"

        Write-Host "Generating AD users and groups..." -ForegroundColor Green
        & "$(Split-Path $MyInvocation.MyCommand.Path)/GenerateIdentities.ps1"

        Write-Host "Generating OU structure..." -ForegroundColor Green
        & "$(Split-Path $MyInvocation.MyCommand.Path)/CreateOU.ps1"
        
        Write-Host "Creating GPOs..." -ForegroundColor Green
        & "$(Split-Path $MyInvocation.MyCommand.Path)/GPOCreation.ps1"
        
        Write-Host "Creating malicious user and backdoor..." -ForegroundColor Green
        & "$(Split-Path $MyInvocation.MyCommand.Path)/Malicious.ps1"
        
        Write-Host "Injecting additional vulnerabilities..." -ForegroundColor Green
        & "$(Split-Path $MyInvocation.MyCommand.Path)/Vulnerabilities.ps1"
        
        Write-Host "Coping files and installing SSH..." -ForegroundColor Green
        & "$(Split-Path $MyInvocation.MyCommand.Path)/InstallAPPs.ps1"
        
        Write-Host "Creating user profiles and SSH keys....." -ForegroundColor Green
        & "$(Split-Path $MyInvocation.MyCommand.Path)/CreateSpecialUserProfiles.ps1"

        Write-Host "AD setup completed successfully!" -ForegroundColor Green
        Write-Host ""
        
        # Clean up: Remove the registry key and scheduled task if no longer needed
        Write-Host "Removing registry entries and scheduled task..." -ForegroundColor Yellow
        Write-Host ""
        Remove-Item -Path "HKLM:\Software\ADAutomationSuite" 
        Unregister-ScheduledTask -TaskName "ContinueAfterReboot" -Confirm:$false

        # Self-Destruct: Delete the installation files
        # Comment out the following lines if you want to keep the installation scripts
        $ProjectRoot = Split-Path -Path $PSScriptRoot -Parent
        Write-Host "Cleaning up installation files in $ProjectRoot..." -ForegroundColor Yellow
        try {
            Remove-Item -Path $ProjectRoot -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Host "Could not remove installation directory. Please delete manually: $ProjectRoot" -ForegroundColor Red
        }
        # --------------------------- Until here ---------------------------
        
        # Final reboot to apply all changes
        Write-Host "Rebooting the system in 60 Seconds to finalize the setup... " -ForegroundColor Green
        Write-Host "You don't need to read all that is above, just wait for the reboot :)" -ForegroundColor Green
        start-sleep -s 60 # time to read the script output
        Restart-Computer -Force # Commenting out for testing purposes
    }
}
else{
    
    # On the first run, check if AD DS is already installed
    $testdc = Get-Windowsfeature | ? {$_.Name -LIKE "AD-Domain-Services" -and $_.InstallState -eq "Installed"}
    if ($testdc){
        Write-Host "AD-Domain-Services already installed" -ForegroundColor Magenta
        Write-Host "Exiting script." -ForegroundColor Magenta
        break
    }
    
    $DomainName = Read-Host "Enter the Domain Name (e.g., vuln.local)"
    Write-Host "[!] IMPORTANT: After you enter the Password, don't touch on the terminal!!" -ForegroundColor Green
    Write-Host "If you do it, it will break the AD installation." -ForegroundColor Green
    Write-Host "This is not a BUG, it's a feature. Thanks Microsoft!" -ForegroundColor Yellow
    Write-Host "p.s. I could probably try to fix this, but I don't want :D sorry, not sorry" -ForegroundColor Cyan
    Write-Host ""
    $password = Read-Host "Enter Safe Mode Admin Password" -AsSecureString

    Write-Host ""
    Write-Host "Starting to install..." -ForegroundColor Green
	Write-Host "Creating registry entries to continue configuration after boot..." -ForegroundColor Green
    
    # Set a registry to indicate the script has run
	New-Item -Path "HKLM:\Software\ADAutomationSuite" -Force | Out-Null
	New-ItemProperty -Path "HKLM:\Software\ADAutomationSuite" -Name "ISRun" -Value "true" -PropertyType "String" -Force | Out-Null
    
    # Schedule this script to run at next logon
    $scriptPath = "$PSScriptRoot\$(Split-Path -Path $MyInvocation.MyCommand.Path -Leaf)"
    $actionArgs = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Normal -File `"$scriptPath`""
    $action = New-ScheduledTaskAction -Execute 'Powershell.exe' -Argument $actionArgs
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $principal = New-ScheduledTaskPrincipal -UserId "Administrator" -LogonType Interactive -RunLevel Highest
    $setting = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -TaskName "ContinueAfterReboot" -Settings $setting -Force | Out-Null


    # Install AD DS and promote to domain controller
    Write-Host "Installing AD DS..." -ForegroundColor Red
    Write-Host ""
    Write-Host ""
    try {
        Install-WindowsFeature AD-Domain-Services -IncludemanagementTools `
        -WarningAction SilentlyContinue `
        -ErrorAction Stop | Out-Null
        Write-Host "AD-Domain-Services installed successfully." -ForegroundColor Green
        Write-Host ""
        Write-Host ""
        Write-Host "Proceeding with domain controller setup." -ForegroundColor Yellow
    }
    catch {
        Write-Host "Failed to install AD-Domain-Services. Exiting script." -ForegroundColor Red
        Write-Host "Error Detail: $($_.Exception.Message)" -ForegroundColor White
        # Clean up: Remove the registry key and scheduled task if installation fails
        Remove-Item -Path "HKLM:\Software\ADAutomationSuite" -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName "ContinueAfterReboot" -Confirm:$false -ErrorAction SilentlyContinue
        Read-Host "Press Enter to exit..."
        exit
    }
    Import-Module ADDSDeployment
    try {
    Write-Host ""
    Write-Host "Promoting DC to Domain Controller..." -ForegroundColor Green
    Write-Host ""
    Install-ADDSForest `
        -DomainName $DomainName `
        -SafeModeAdministratorPassword $password `
        -InstallDNS `
        -Force:$true `
        -WarningAction SilentlyContinue `
        -ErrorAction Stop | Out-Null
    Write-Host "Domain Controller promoted successfully. The system will now reboot." -ForegroundColor Green
    Write-Host ""
    Write-Host "The script will continue after reboot to finalize the setup." -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to promote to Domain Controller. Exiting script." -ForegroundColor Red
        Write-Host "Error Detail: $($_.Exception.Message)" -ForegroundColor White
        # Clean up: Remove the registry key and scheduled task if promotion fails
        Remove-Item -Path "HKLM:\Software\ADAutomationSuite" -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName "ContinueAfterReboot" -Confirm:$false -ErrorAction SilentlyContinue
        Read-Host "Press Enter to exit..."
        exit
    }
}