<#
.SYNOPSIS
    Establishes the Organizational Unit (OU) structure and organizes AD objects.

.DESCRIPTION
    Creates a hierarchical OU structure under a root domain OU. 
    OUs created: Computers, Users, Groups, and Admins (under Users).
    Automatically relocates newly created users and groups from default containers to the new structure.
    Also selects random members from 'IT Department' to elevate to Domain Admins for the scenario.
#>

# Define variables based on current AD domain
$domain = (Get-ADDomain).Name
$DomainDN = (Get-ADDomain).DistinguishedName

# Create root OU for the organization. I think it makes more sense to have it all under a main OU.
New-ADOrganizationalUnit -Name "$domain" -Path "$DomainDN"

# Create Computer, Users, Groups and Admins OUs
# You can add more OUs here if you want to expand the structure.
New-ADOrganizationalUnit -Name "Computers" -Path "OU=$domain,$DomainDN" | Out-Null
Write-Host "Created OU: Computers" -ForegroundColor Cyan
New-ADOrganizationalUnit -Name "Users" -Path "OU=$domain,$DomainDN" | Out-Null
Write-Host "Created OU: Users" -ForegroundColor Cyan
New-ADOrganizationalUnit -Name "Groups" -Path "OU=$domain,$DomainDN" | Out-Null
Write-Host "Created OU: Groups" -ForegroundColor Cyan
New-ADOrganizationalUnit -Name "Admins" -Path "OU=Users,OU=$domain,$DomainDN" | Out-Null
Write-Host "Created OU: Admins" -ForegroundColor Cyan

# Move existing users and groups to their respective OUs
Get-ADUser -Filter * | Where-Object {$_.Surname -ne $null } | ForEach-Object {
    $userDN = $_.DistinguishedName
    Move-ADObject -Identity $userDN -TargetPath "OU=Users,OU=$domain,$DomainDN" | Out-Null
}
Write-Host " [+] Moved all created users to OU: 'Users'" -ForegroundColor Green

# Move groups to Groups OU
$GroupDN = Get-ADGroup -Filter * -Properties isCriticalSystemObject | Where-Object {
    $_.isCriticalSystemObject -ne $true -and 
    $_.DistinguishedName -notlike "*CN=Dns*,DC=*" -and 
    $_.DistinguishedName -notlike "*CN=Builtin,DC=*"
}
$GroupDN | Move-ADObject -TargetPath "OU=Groups,OU=$domain,$DomainDN" | Out-Null
$GroupDN | ForEach-Object {
}
Write-Host " [+] Moved all created groups to OU: 'Groups'" -ForegroundColor Green

# Move computer accounts to Computers OU
Get-ADGroupMember "Domain Computers" | ForEach-Object {
    $computerDN = $_.distinguishedName
    Move-ADObject -Identity $computerDN -TargetPath "OU=Computers,OU=$domain,$DomainDN" | Out-Null
}

# Add random users from the IT Department group to Domain Admins
Get-ADGroupMember "IT Department" | Get-Random -Count "3" | ForEach-Object {
    $UserName = $_.Name
    $UserGUID = $_.ObjectGUID

    Add-ADGroupMember -Identity "Domain Admins" -Members $UserGUID | Out-Null
    Move-ADObject -Identity $UserGUID -TargetPath "OU=Admins,OU=Users,OU=$domain,$DomainDN" | Out-Null
    Write-Host " [+] Added user: $UserName to Domain Admins group" -ForegroundColor Cyan
}
Write-Host ""