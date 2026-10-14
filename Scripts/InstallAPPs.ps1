<#
.SYNOPSIS
    Install additional applications and (.........), such as OpenSSH Server.

.DESCRIPTION
    Copy files from Software directory to "C:\Program Files\OpenSSH-Win64" on the server to install OpenSSH Server.
    Add more lines for additional applications
#>

# Define source and destination paths for OpenSSH Server
$sourcePath = "$(Split-Path $MyInvocation.MyCommand.Path)\Software\OpenSSH-Win64"
$destinationPath = "C:\Program Files\OpenSSH-Win64"
if ((Get-WmiObject -class Win32_OperatingSystem).Caption -like "*Server 2016*") {
    Write-Host "Windows Server 2016 detected, proceeding with OpenSSH installation..." -ForegroundColor Green
    Write-Host ""
    # Check if the source directory exists
    if (Test-Path -Path $sourcePath) {
        if (-not (Test-Path -Path $destinationPath)) {
            New-Item -ItemType Directory -Path $destinationPath | Out-Null
        }
        Copy-Item -Path "$sourcePath\*" -Destination $destinationPath -Recurse -Force
        Write-Host " [+] OpenSSH Server files copied to $destinationPath" -ForegroundColor Green
    } else {
        Write-Host " [!] Source directory for OpenSSH Server not found: $sourcePath" -ForegroundColor Red
    }

    # Set the Path system environment variable:
    Write-Host " [+] Adding OpenSSH to system PATH..." -ForegroundColor Green
    setx PATH "$env:path;C:\Program Files\OpenSSH-Win64" -m

    # Run SSH installation script:
    Write-Host " [+] Installing OpenSSH Server..." -ForegroundColor Green
    & "C:\Program Files\OpenSSH-Win64\install-sshd.ps1"

    # Set OpenSSH services to start automatically and start the services
    Write-Host " [+] Configuring OpenSSH services..." -ForegroundColor Green
    Set-Service sshd -StartupType Automatic; Set-Service ssh-agent -StartupType Automatic; Start-Service sshd; Start-Service ssh-agent

    # Add firewall rules for OpenSSH
    Write-Host " [+] Adding firewall rules for OpenSSH..." -ForegroundColor Green
    New-NetFirewallRule -DisplayName "Allow OpenSSH" -Direction Inbound -LocalPort 22 -Protocol TCP -Action Allow
} else {
    Write-Host "This script is designed for Windows Server 2016. Detected OS: $((Get-WmiObject -class Win32_OperatingSystem).Caption)" -ForegroundColor Red
    Write-Host "Skipping OpenSSH installation." -ForegroundColor Yellow
}

Function Enable-RDP {
    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -Value 0
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

}

Enable-RDP