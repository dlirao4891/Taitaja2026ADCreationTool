<#
.SYNOPSIS
    Create user profiles and plant simulated SSH keys.

.DESCRIPTION
    This script creates a user profile for a specified AD user and simulates the presence of SSH keys in their profile. 
    It uses the Win32 API to create the profile and then drops fake SSH keys in the .ssh folder of the user's profile directory.
    I got the base for the script from this post: https://www.reddit.com/r/PowerShell/comments/smxtq7/i_need_to_create_user_profile_folders_on_300/
    I then used AI to adapt the code to work on AD. And I don't have any problem to say, that I don't fully understand how it works. 
    But it works! Added after the ssh-keygen, it will create a new key pair for the user and set the correct permissions on the private key.
#>

# 1. Elevate and Check AD
if (-not (Get-Module -ListAvailable ActiveDirectory)) {
    Write-Error "AD Module required for DC simulation."; return
}

# 2. Win32 API Definition
$TypeDefinition = @"
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace UserProfile {
    public static class Win32 {
        [DllImport("userenv.dll", SetLastError = true, CharSet = CharSet.Auto)]
        public static extern int CreateProfile(
            [MarshalAs(UnmanagedType.LPWStr)] string pszUserSid,
            [MarshalAs(UnmanagedType.LPWStr)] string pszUserName,
            [Out][MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszProfilePath,
            uint cchProfilePath
        );
    }
}
"@
if (-not ([System.Management.Automation.PSTypeName]'UserProfile.Win32').Type) { Add-Type -TypeDefinition $TypeDefinition }

# 3. Get the users from the "Linux Users" group and create profile plus ssh keys.
$Users = @(Get-ADGroupMember -Identity "Linux Users" -Recursive | Where-Object { $_.objectClass -eq "user" } | Select-Object -ExpandProperty SamAccountName)
foreach ($TargetUser in $Users) {
    
    try {
        $ADUser = Get-ADUser -Identity $TargetUser -ErrorAction Stop
        $Buffer = New-Object System.Text.StringBuilder(260)
        
        Write-Host "[+] Creating Profile for $TargetUser..." -ForegroundColor Cyan
        $Result = [UserProfile.Win32]::CreateProfile($ADUser.SID.Value, $ADUser.SamAccountName, $Buffer, 260)
        
        if ($Result -eq 0 -or $Result -eq -2147024713) {
            $ProfilePath = $Buffer.ToString()
            if ([string]::IsNullOrWhiteSpace($ProfilePath)) { 
                # Fallback if profile existed but buffer didn't populate
                $ProfilePath = "C:\Users\$TargetUser" 
            }
            
            $SSHPath = Join-Path $ProfilePath ".ssh\"
            
            # Create .ssh folder if missing
            if (-not (Test-Path $SSHPath)) {
                New-Item -Path $SSHPath -ItemType Directory -Force | Out-Null
            }
            & 'C:\Program Files\OpenSSH-Win64\ssh-keygen.exe' -t ed25519 -f $SSHPath\id_ed25519 -N "" -q | Out-Null
            
            # Set strict permissions (standard for SSH keys)
            $PrivateKeyPath = Join-Path $SSHPath "id_ed25519"
            $Acl = Get-Acl $PrivateKeyPath
            $Ar = New-Object System.Security.AccessControl.FileSystemAccessRule($ADUser.SamAccountName, "FullControl", "Allow")
            $Acl.SetAccessRule($Ar)
            Set-Acl $PrivateKeyPath $Acl
            
            Write-Host "[!] Success: SSH keys created for $TargetUser." -ForegroundColor Green
        }
    }
    catch {
        Write-Host "[-] Failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}