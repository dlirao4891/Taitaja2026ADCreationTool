<#
.SYNOPSIS
    Generates a structured JSON file for AD object creation.

.DESCRIPTION
    Parses source text files (names, surnames, group names, passwords) and generates 
    a 'users_and_groups.json' file. It handles international character encoding (åäö) 
    and ensures unique object generation. The resulting JSON is used by GenerateIdentities.ps1.
#>

# Fix line breaking and encoding issues by enforcing UTF8.
$DataFiles = @("group_names.txt", "name.txt", "surname.txt", "passwords.txt")
foreach ($file in $DataFiles) {
    $path = "$PSScriptRoot\Data\$file"
    if (Test-Path $path) {
        $content = Get-Content $path -Encoding UTF8
        [System.IO.File]::WriteAllLines($path, $content)
    }
}

# Create ArrayLists using existing files.
$group_names = [System.Collections.ArrayList](Get-Content "$PSScriptRoot\Data\group_names.txt")
$first_names = [System.Collections.ArrayList](Get-Content "$PSScriptRoot\Data\name.txt")
$last_names = [System.Collections.ArrayList](Get-Content "$PSScriptRoot\Data\surname.txt")
$passwords = [System.Collections.ArrayList](Get-Content "$PSScriptRoot\Data\passwords.txt")

# Create empty arrays for users and groups.
$groups = @( @{ "name" = "IT Department" } )
$group_names.Remove("IT Department")
$users = @()

# Create a list of 6 more groups (total 7) from the existing ones and makes sure they are unique.
$num_groups = 6
for ( $i = 0; $i -lt $num_groups; $i++ ){
    $new_group = (Get-Random -InputObject $group_names)
    $new_group = ($new_group -replace "å","a")
    $new_group = ($new_group -replace "ä","a")
    $new_group = ($new_group -replace "ö","o")
    $groups += @{ "name" = $new_group }
    $group_names.Remove($new_group)
}

# Create a list of 50 users containing first_name, last_name and password and makes sure they are unique.
$num_users = 50
for ( $i = 0; $i -lt $num_users; $i++ ){
    $first_name = (Get-Random -InputObject $first_names) 
    $first_name = ($first_name -replace "å","a")
    $first_name = ($first_name -replace "ä","a")
    $first_name = ($first_name -replace "ö","o")
    
    $last_name = (Get-Random -InputObject $last_names)
    $last_name = ($last_name -replace "å","a")
    $last_name = ($last_name -replace "ä","a")
    $last_name = ($last_name -replace "ö","o")

    $password = (Get-Random -InputObject $passwords)
    $new_user = @{
        "name" = "$first_name $last_name"
        "password" = "$password"
        "groups" = @( (Get-Random -InputObject $groups.name) )
    }

    $users += $new_user
    $first_names.Remove($first_name)
    $last_names.Remove($last_name)
    $passwords.Remove($password)
}
# Get domain name
$domain = (Get-ADDomain).Name

# Write the file out
echo @{
    "domain" = "$domain"
    "groups" = $groups
    "users" = $users
} | ConvertTo-Json | Out-File $PSScriptRoot/Data/users_and_groups.json -Encoding UTF8