# ============================================================
# Script: AddUsers
#
# Description:
# Automatically generates randomized Active Directory user
# accounts to populate a lab environment with realistic
# identities. Supports hybrid enterprise simulation and
# security research scenarios that require multiple user
# objects for authentication, telemetry, and behavioral testing.
#
# Intended for controlled lab environments only.
# Uses a shared default password for simplicity.
# Not suitable for production use.
# ============================================================
 
# ==============================
# CONFIGURATION
# ==============================

$NumberOfUsers = 15
$Domain        = "<insertdoamin>"
$OU            = "CN=Users,DC=<>,DC=<>"
$DefaultPass   = "P@ssw0rd123!" | ConvertTo-SecureString -AsPlainText -Force   # Plain text because this is a lab

# ==============================
# NAME LISTS (US-Common)
# ==============================

$FirstNames = @(
    "James","John","Robert","Michael","William",
    "David","Richard","Joseph","Thomas","Charles",
    "Mary","Patricia","Jennifer","Linda","Elizabeth",
    "Barbara","Susan","Jessica","Sarah","Karen"
)

$LastNames = @(
    "Smith","Johnson","Williams","Brown","Jones",
    "Garcia","Miller","Davis","Rodriguez","Martinez",
    "Hernandez","Lopez","Gonzalez","Wilson","Anderson"
)

# ==============================
# CREATE USERS
# ==============================

for ($i = 1; $i -le $NumberOfUsers; $i++) {

    $FirstName = Get-Random $FirstNames
    $LastName  = Get-Random $LastNames

    $Sam = ($FirstName.Substring(0,1) + $LastName).ToLower()

    # Ensure uniqueness
    if (Get-ADUser -Filter "SamAccountName -eq '$Sam'" -ErrorAction SilentlyContinue) {
        $Sam = "$Sam$i"
    }

    $UPN = "$Sam@$Domain"
    $Name = "$FirstName $LastName"

    Write-Host "Creating user: $Name ($Sam)"

    New-ADUser `
        -Name $Name `
        -GivenName $FirstName `
        -Surname $LastName `
        -SamAccountName $Sam `
        -UserPrincipalName $UPN `
        -AccountPassword $DefaultPass `
        -Enabled $true `
        -ChangePasswordAtLogon $true `
        -Path $OU
}

Write-Host "`n✅ $NumberOfUsers test users created successfully."

