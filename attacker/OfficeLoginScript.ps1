# === CONFIG ===
$TenantId  = "8202a09f-5a9d-496f-ab6b-13f877672c67"
$ClientId  = "8d4fd7dd-f222-41c2-80e1-3498c5ece087"   # Public client app (no secret)
$Scopes = "openid profile offline_access User.Read User.ReadBasic.All"

#$Scopes    = "https://graph.microsoft.com/User.Read offline_access openid profile"

$Users = @(
"bhernandez@kidsreadingroad.com",
"cdavis@kidsreadingroad.com",
"ddavis@kidsreadingroad.com",
"ebrown@kidsreadingroad.com",
"jmartinez@kidsreadingroad.com",
"jmiller@kidsreadingroad.com",
"krodriguez@kidsreadingroad.com",
"plopez@kidsreadingroad.com",
"rwilson@kidsreadingroad.com",
"sbrown@kidsreadingroad.com",
"swilson@kidsreadingroad.com",
"twilliams@kidsreadingroad.com",
"twilson@kidsreadingroad.com",
"wanderson@kidsreadingroad.com",
"TestUser1@kidsreadingroad.com",
"TestUser2@kidsreadingroad.com",
"TestUser3@kidsreadingroad.com",
"TestUser4@kidsreadingroad.com"
)

$Password  = "P@ssw0rd123!"  # Ideally pulled from a secure store, not hard-coded

# === TOKEN (ROPC) ===
$tokenUri = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

foreach ($Upn in $Users) {

    $body = @{
        client_id  = $ClientId
        scope      = $Scopes
        grant_type = "password"
        username   = $Upn
        password   = $Password
    }

    $token = Invoke-RestMethod `
        -Method Post `
        -Uri $tokenUri `
        -Body $body `
        -ContentType "application/x-www-form-urlencoded"

    $accessToken = $token.access_token

    # === CALL GRAPH: /me ===
    $headers = @{
        Authorization = "Bearer $accessToken"
    }

    $me = Invoke-RestMethod `
        -Method Get `
        -Uri "https://graph.microsoft.com/v1.0/me" `
        -Headers $headers

    $me | Select-Object displayName, userPrincipalName

    # === CALL GRAPH: getMemberObjects ===
    $jsonBody = @{
        securityEnabledOnly = $false
    } | ConvertTo-Json

    $groups = Invoke-RestMethod `
        -Method Post `
        -Uri "https://graph.microsoft.com/v1.0/me/getMemberObjects" `
        -Headers @{
            Authorization = "Bearer $accessToken"
            "Content-Type" = "application/json"
        } `
        -Body $jsonBody

    $groups.value

}
