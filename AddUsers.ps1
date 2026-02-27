# ==============================
# CONFIGURATION
# ==============================

$NumberOfUsers = 15
$Domain        = "kidsreadingroad.com"
$OU            = "CN=Users,DC=KidsReadingRoad,DC=com"
$DefaultPass   = "P@ssw0rd123!" | ConvertTo-SecureString -AsPlainText -Force

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
