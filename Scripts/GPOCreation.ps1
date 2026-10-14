<#
.SYNOPSIS
    Deploys both standard and intentionally flawed Group Policy Objects (GPOs).

.DESCRIPTION
    This script automates the creation and linking of several GPOs to demonstrate
    common misconfigurations and security flaws in an Active Directory environment.

    Standard GPOs: Wallpaper, Power Management, Task Manager restriction, Drive Mapping.
    Flawed GPOs: SMBv1/WDigest enablement, weak encryption, LLMNR enablement, RDP exposure,
                and Local Admin rights abuse (via Restricted Groups).
#>
$dc = (Get-ADDomainController).HostName
$domain = (Get-ADDomain).Name
$DomainDN = (Get-ADDomain).DistinguishedName
$DomainFQDN = (Get-ADDomain).DNSRoot
$rootOUPath = "OU=$domain,$DomainDN"
$DCOUPath = "OU=Domain Controllers,$DomainDN"
$CompOUPath = "OU=Computers,OU=$domain,$DomainDN"
$UsersOUPath = "OU=Users,OU=$domain,$DomainDN"

#---------------------------------------- Create basic GPOs for the domain

$DeskWallPaper = "Default Desktop WallPaper"
$Path = "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System"
New-GPO -Name $DeskWallPaper -Server $dc -Comment "Sets the standard corporate wallpaper" | Out-Null
Set-GPRegistryValue -Name $DeskWallPaper -Key $Path -ValueName "Wallpaper" -Type String -Value "C:\Windows\Web\Wallpaper\Corporate_Wall.jpg" | Out-Null
Set-GPRegistryValue -Name $DeskWallPaper -Key $Path -ValueName "WallpaperStyle" -Type String -Value "4" | Out-Null
New-GPLink -Name $DeskWallPaper -Target $CompOUPath -Server $dc | Out-Null
Write-Host " [+] Created GPO: $DeskWallPaper" -ForegroundColor Green

$Power = "Power Management"
New-GPO -Name $Power -Server $dc -Comment "Sets High Performance Power Plan and disable sleep, like our workers" | Out-Null
Set-GPPrefRegistryValue -Name $Power -Context Computer -Action Create `
    -Key "HKLM\Software\Microsoft\Windows\CurrentVersion\explorer\ControlPanel\NameSpace\{021E2840-7712-11D3-9399-4400F7F36F28}" `
    -ValueName "PreferredPlan" -Value "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c" -Type String | Out-Null
Set-GPPrefRegistryValue -Name $Power -Context Computer -Action Create `
    -Key "HKLM\System\CurrentControlSet\Control\Power\User\PowerSchemes\8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c\238c9fe8-0427-4147-bc3e-4f08bfd173f2\29f72528-3395-4a21-8813-22295933c856" `
    -ValueName "ACSettingIndex" -Value 0 -Type DWord | Out-Null
New-GPLink -Name $Power -Target $CompOUPath -Server $dc | Out-Null
Write-Host " [+] Created GPO: $Power" -ForegroundColor Green

$TaskManager = "Restrict TaskManager"
$Path = "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System"
New-GPO -Name $TaskManager -Server $dc -Comment "Disables Task Manager for users" | Out-Null
Set-GPRegistryValue -Name $TaskManager -Key $Path -ValueName "DisableTaskMgr" -Type DWord -Value 1 | Out-Null
New-GPLink -Name $TaskManager -Target $UsersOUPath -Server $dc | Out-Null
Write-Host " [+] Created GPO: $TaskManager" -ForegroundColor Green

$Drive = "Drive Mapping"
New-GPO -Name $Drive -Server $dc -Comment "Maps P: drive to Shared Folder" | Out-Null
Set-GPPrefRegistryValue -Name $Drive -Context User -Action Create -Key "HKCU\Network\P" -ValueName "RemotePath" -Type String -Value "\\FS01\Public" | Out-Null
New-GPLink -Name $Drive -Target $UsersOUPath -Server $dc | Out-Null
Write-Host " [+] Created GPO: $Drive" -ForegroundColor Green

$HomePage = "Browser Settings"
$Path = "HKCU\Software\Policies\Microsoft\Internet Explorer\Main"
New-GPO -Name $HomePage -Server $dc -Comment "Sets corporate home page" | Out-Null
Set-GPRegistryValue -Name $HomePage -Key $Path -ValueName "Start Page" -Type String -Value "https://intranet.vuln.local" | Out-Null
New-GPLink -Name $HomePage -Target $UsersOUPath -Server $dc | Out-Null
Write-Host " [+] Created GPO: $HomePage" -ForegroundColor Green

#---------------------------------------- Modify Default Domain Controllers Policy for RDP Access
# This part was made using AI. And I'm not ashamed of it. But I had to fix one error in it. :/

$AdminSID = "*S-1-5-32-544"
$GroupName = "Linux Users"
$LinuxGroup = Get-ADGroup -Identity $GroupName -ErrorAction SilentlyContinue

if ($LinuxGroup) {
    $LinuxGroupSID = "*$($LinuxGroup.SID.Value)"

    # Grab the Default Domain Controllers Policy
    $DDCP = Get-GPO -Name "Default Domain Controllers Policy"
    $SysVolPath = "\\$DomainFQDN\SysVol\$DomainFQDN\Policies\{$($DDCP.Id)}\Machine\Microsoft\Windows NT\SecEdit"
    $InfFile = "$SysVolPath\GptTmpl.inf"

    if (Test-Path $InfFile) {
        $Content = Get-Content $InfFile

        if ($Content -match "SeRemoteInteractiveLogonRight") {
            # Check if our group is already in there to prevent duplicate SID entries
            if ($Content -notmatch $LinuxGroupSID) {
                $Content = $Content -replace "(SeRemoteInteractiveLogonRight\s*=\s*)(.*)", "`$1`$2,$LinuxGroupSID"
                $Content | Out-File $InfFile -Encoding Unicode
                Write-Host " [+] Appended $GroupName to RDP rights in Default Domain Controllers Policy" -ForegroundColor Green
            } else {
                Write-Host " [i] $GroupName is already present in the RDP rights." -ForegroundColor Yellow
            }
        } else {
            $NewContent = @()
            $Inserted = $false
            foreach ($line in $Content) {
                $NewContent += $line
                if ($line -match "^\[Privilege Rights\]" -and -not $Inserted) {
                    $NewContent += "SeRemoteInteractiveLogonRight = $LinuxGroupSID,$AdminSID"
                    $Inserted = $true
                }
            }

            if (-not $Inserted) {
                $NewContent += "[Privilege Rights]"
                $NewContent += "SeRemoteInteractiveLogonRight = $LinuxGroupSID,$AdminSID"
            }

            $NewContent | Out-File $InfFile -Encoding Unicode
            Write-Host " [+] Added $GroupName to RDP rights in Default Domain Controllers Policy" -ForegroundColor Green
        }

        # Ensure the Security Client Side Extension (CSE) is registered
        # (The Default DC Policy usually has this by default, but this ensures it fires properly)
        $AdPath = "CN={$($DDCP.Id)},CN=Policies,CN=System,$DomainDN"
        $DDCPObj = Get-ADObject -Identity $AdPath -Properties gPCMachineExtensionNames
        if ($DDCPObj.gPCMachineExtensionNames -notmatch "827D319E-6EAC-11D2-A4EA-00C04F79F83A") {
            Set-ADObject -Identity $AdPath -Replace @{gPCMachineExtensionNames="[{827D319E-6EAC-11D2-A4EA-00C04F79F83A}{803E14A0-D4D1-11D1-2244-00C04F79F83A}]"}
        }

    } else {
        Write-Host " [-] Could not find GptTmpl.inf for Default Domain Controllers Policy!" -ForegroundColor Red
    }
} else {
    Write-Host " [-] Group '$GroupName' not found! Make sure you create it earlier in the script." -ForegroundColor Red
}
################## It goes until here the AI helps....

#---------------------------------------- Create flawed GPOs

$Legacy = "Backwards Compatibility"
New-GPO -Name $Legacy -Server $dc -Comment "Enables Legacy Protocols to work with old computers from our network" | Out-Null
# New version - doesn't quite work...
#Set-GPPrefRegistryValue -Name $Legacy -Context Computer -Action Create -Server $dc -Key "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -ValueName "SMB1" -Value 1 -Type DWord | Out-Null
#Set-GPPrefRegistryValue -Name $Legacy -Context Computer -Action Create -Server $dc -Key "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest" -ValueName "UseLogonCredential" -Value 1 -Type DWord | Out-Null
#Set-GPPrefRegistryValue -Name $Legacy -Context Computer -Action Create -Server $dc -Key "HKLM\Software\Policies\Microsoft\Windows\Installer" -ValueName "AlwaysInstallElevated" -Value 1 -Type DWord | Out-Null
#Set-GPPrefRegistryValue -Name $Legacy -Context User -Action Create -Server $dc -Key "HKCU\Software\Policies\Microsoft\Windows\Installer" -ValueName "AlwaysInstallElevated" -Value 1 -Type DWord | Out-Null
# Old version
Set-GPRegistryValue -Name $Legacy -Server $dc -Key "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -ValueName "SMB1" -Type DWord -Value 1 | Out-Null
Set-GPRegistryValue -Name $Legacy -Server $dc -Key "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest" -ValueName "UseLogonCredential" -Type DWord -Value 1 | Out-Null
Set-GPRegistryValue -Name $Legacy -Server $dc -Key "HKLM\Software\Policies\Microsoft\Windows\Installer" -ValueName "AlwaysInstallElevated" -Type DWord -Value 1 | Out-Null
Set-GPRegistryValue -Name $Legacy -Server $dc -Key "HKCU\Software\Policies\Microsoft\Windows\Installer" -ValueName "AlwaysInstallElevated" -Type DWord -Value 1 | Out-Null
New-GPLink -Name $Legacy -Target $rootOUPath -Server $dc | Out-Null
New-GPLink -Name $Legacy -Target $DCOUPath -Server $dc | Out-Null
Write-Host " [!] Created Flawed GPO: $Legacy" -ForegroundColor Red

$Crypto = "Encryption"
$GPO_Crypto = New-GPO -Name $Crypto -Server $dc -Comment "Allows Kerberos to work with legacy devices"
$GPOID_Crypto = $GPO_Crypto.Id
$SysVolPath_Crypto = "\\$DomainFQDN\SysVol\$DomainFQDN\Policies\{$GPOID_Crypto}\Machine\Microsoft\Windows NT\SecEdit"

New-Item -Path $SysVolPath_Crypto -ItemType Directory -Force | Out-Null

$Content_Crypto = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[Registry Values]
MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\Kerberos\Parameters\SupportedEncryptionTypes=4,2147483647
"@
$Content_Crypto | Out-File "$SysVolPath_Crypto\GptTmpl.inf" -Encoding Unicode

# Register the Client Side Extension (CSE) - This is to make it work on the GPO GUI
$AdPath_Crypto = "CN={$GPOID_Crypto},CN=Policies,CN=System,$DomainDN"
Set-ADObject -Identity $AdPath_Crypto -Replace @{gPCMachineExtensionNames="[{827D319E-6EAC-11D2-A4EA-00C04F79F83A}{803E14A0-D4D1-11D1-2244-00C04F79F83A}]"}

New-GPLink -Name $Crypto -Target $rootOUPath -Server $dc | Out-Null
New-GPLink -Name $Crypto -Target $DCOUPath -Server $dc | Out-Null
Write-Host " [!] Created Flawed GPO: $Crypto" -ForegroundColor Red

$LLMNR = "Disable LLMNR and NBNS"
New-GPO -Name $LLMNR -Server $dc -Comment "Ensures that LLMNR and NBNS are disabled" | Out-Null
Set-GPRegistryValue -Name $LLMNR -Server $dc -Key "HKLM\Software\Policies\Microsoft\Windows NT\DNSClient" -ValueName "EnableMulticast" -Type DWord -Value 1 | Out-Null
New-GPLink -Name $LLMNR -Target $rootOUPath -Server $dc | Out-Null
New-GPLink -Name $LLMNR -Target $DCOUPath -Server $dc | Out-Null
Write-Host " [!] Created Flawed GPO: $LLMNR" -ForegroundColor Red

$RDP = "Remote Access"
New-GPO -Name $RDP -Server $dc -Comment "Enable Remote Desktop access" | Out-Null
Set-GPRegistryValue -Name $RDP -Server $dc -Key "HKLM\Software\Policies\Microsoft\Windows NT\Terminal Services" -ValueName "fDenyTSConnections" -Type DWord -Value 0 | Out-Null
Set-GPRegistryValue -Name $RDP -Server $dc -Key "HKLM\Software\Policies\Microsoft\Windows NT\Terminal Services" -ValueName "UserAuthentication" -Type DWord -Value 0 | Out-Null
Set-GPRegistryValue -Name $RDP -Server $dc -Key "HKLM\Software\Policies\Microsoft\Windows NT\Terminal Services" -ValueName "SecurityLayer" -Type DWord -Value 0 | Out-Null
# New version - doesn't quite work...
#Set-GPPrefRegistryValue -Name $RDP -Context Computer -Action Create -Server $dc -Key "HKLM\Software\Policies\Microsoft\Windows NT\Terminal Services" -ValueName "fDenyTSConnections" -Value 0 -Type DWord | Out-Null
#Set-GPPrefRegistryValue -Name $RDP -Context Computer -Action Create -Server $dc -Key "HKLM\Software\Policies\Microsoft\Windows NT\Terminal Services" -ValueName "UserAuthentication" -Value 0 -Type DWord | Out-Null
#Set-GPPrefRegistryValue -Name $RDP -Context Computer -Action Create -Server $dc -Key "HKLM\Software\Policies\Microsoft\Windows NT\Terminal Services" -ValueName "SecurityLayer" -Value 0 -Type DWord | Out-Null
New-GPLink -Name $RDP -Target $rootOUPath -Server $dc | Out-Null
New-GPLink -Name $RDP -Target $DCOUPath -Server $dc | Out-Null
Write-Host " [!] Created Flawed GPO: $RDP" -ForegroundColor Red

$ITAdmin = "Local Admins"
$TargetGroupSID = "S-1-5-32-544" #SID for built-in Administrators
$MemberToAdd = "Domain Users"

$GPO = New-GPO -Name $ITAdmin -Server $dc -Comment "Adds IT Admins to Local Administrators group"
$GPOID = $GPO.Id
$SysVolPath = "\\$DomainFQDN\SysVol\$DomainFQDN\Policies\{$GPOID}\Machine\Microsoft\Windows NT\SecEdit"

New-Item -Path $SysVolPath -ItemType Directory -Force | Out-Null

$Content = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[Group Membership]
*$TargetGroupSID`__Memberof =
*$TargetGroupSID`__Members = $MemberToAdd
"@
# Write file with Unicode encoding, so it doesn't break
$Content | Out-File "$SysVolPath\GptTmpl.inf" -Encoding Unicode

# Register the Client Side Extension (CSE) - This is to make it work on the GPO GUI
$AdPath = "CN={$GPOID},CN=Policies,CN=System,$DomainDN"
Set-ADObject -Identity $AdPath -Replace @{gPCMachineExtensionNames="[{827D319E-6EAC-11D2-A4EA-00C04F79F83A}{803E14A0-D4D1-11D1-2244-00C04F79F83A}]"}

New-GPLink -Name $ITAdmin -Target $CompOUPath -Server $dc | Out-Null
Write-Host " [!] Created Flawed GPO: $ITAdmin" -ForegroundColor Red

$Printers = "Printer Drivers"
New-GPO -Name $Printers -Server $dc -Comment "Allows users to install printer drivers without admin rights" | Out-Null
Set-GPRegistryValue -Name $Printers -Server $dc -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint" -ValueName "Restricted" -Type DWord -Value 1 | Out-Null
Set-GPRegistryValue -Name $Printers -Server $dc -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint" -ValueName "NoWarningNoElevationOnInstall" -Type DWord -Value 1 | Out-Null
Set-GPRegistryValue -Name $Printers -Server $dc -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint" -ValueName "UpdatePromptSettings" -Type DWord -Value 2 | Out-Null
New-GPLink -Name $Printers -Target $RootOUPath -Server $dc | Out-Null
New-GPLink -Name $Printers -Target $DCOUPath -Server $dc | Out-Null
Write-Host " [!] Created Flawed GPO: $Printers" -ForegroundColor Red

Write-Host ""
