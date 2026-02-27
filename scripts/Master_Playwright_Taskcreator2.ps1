<#
Master_Playwright_TaskCreator.ps1 (NO UNC REQUIRED)

What it does:
1) Generates a minimal Playwright project on the admin box (in %TEMP%)
2) Zips and pushes it to each endpoint -> C:\AtomicRedTeam\Playwright   (via PS Remoting, NOT \\C$)
3) Drops a runner script -> C:\AtomicRedTeam\Run-Playwright.ps1
4) Creates scheduled tasks per user:
     PlaywrightCampaign-<user>  (AtLogOn, runs as that user)
   Exception:
     CLIENT4 runs as labadmin only

Assumptions:
- Node.js + npm installed on endpoints
- Endpoints have internet (to npm install + playwright install)
- You run this as a domain admin (labadmin)

Lab-only warning:
- Passwords are passed as scheduled-task arguments (plaintext on-box). OK for isolated lab; do NOT do this in production.
#>

$ErrorActionPreference = "Stop"

# =====================
# CONFIG
# =====================
$DomainNetbios = "KIDSREADINGROAD"
$PortalUrl     = "https://portal.office.com"

$DefaultUserPassword = "P@ssw0rd123!"
$LabAdminPassword    = "P@ssw0rd"   # for CLIENT4 task args

$RemoteRoot  = "C:\AtomicRedTeam"
$RemotePWDir = Join-Path $RemoteRoot "Playwright"
$RemoteLogs  = Join-Path $RemoteRoot "Logs"
$RunnerPath  = Join-Path $RemoteRoot "Run-Playwright.ps1"

# Users -> machine mapping
$Assignments = @(
  @{ Computer="CLIENT1"; UserSam="bhernandez" },
  @{ Computer="CLIENT1"; UserSam="cdavis" },
  @{ Computer="CLIENT1"; UserSam="ddavis" },
  @{ Computer="CLIENT1"; UserSam="ebrown" },
  @{ Computer="CLIENT1"; UserSam="jmartinez" },
  @{ Computer="CLIENT1"; UserSam="jmiller" },

  @{ Computer="CLIENT2"; UserSam="krodriguez" },
  @{ Computer="CLIENT2"; UserSam="plopez" },
  @{ Computer="CLIENT2"; UserSam="rwilson" },
  @{ Computer="CLIENT2"; UserSam="sbrown" },
  @{ Computer="CLIENT2"; UserSam="swilson" },
  @{ Computer="CLIENT2"; UserSam="twilliams" },

  @{ Computer="CLIENT3"; UserSam="twilson" },
  @{ Computer="CLIENT3"; UserSam="wanderson" },
  @{ Computer="CLIENT3"; UserSam="TestUser1" },
  @{ Computer="CLIENT3"; UserSam="TestUser2" },
  @{ Computer="CLIENT3"; UserSam="TestUser3" },
  @{ Computer="CLIENT3"; UserSam="TestUser4" },

  @{ Computer="CLIENT4"; UserSam="labadmin"; ForceLabAdmin=$true }
)

# OPTION A: Convert hashtables -> PSCustomObject so Select-Object / Group-Object work
$Assignments = $Assignments | ForEach-Object { [pscustomobject]$_ }

# Sanity filter
$Assignments = $Assignments | Where-Object {
  $_.Computer -and $_.Computer.Trim().Length -gt 0 -and $_.UserSam -and $_.UserSam.Trim().Length -gt 0
}
if (-not $Assignments -or $Assignments.Count -eq 0) {
  throw "No valid assignments found. Check the `$Assignments array."
}

Write-Host "PortalUrl: $PortalUrl"
Write-Host "Remote deploy dir: $RemotePWDir"
Write-Host ""
$Assignments | Select-Object Computer, UserSam | Format-Table -AutoSize
Write-Host ""

# =======================================
# 1) BUILD PLAYWRIGHT PROJECT ON THE FLY
# =======================================
$buildRoot = Join-Path $env:TEMP ("PW_PAYLOAD_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
$localProj = Join-Path $buildRoot "Playwright"
$localZip  = Join-Path $env:TEMP "PlaywrightPayload.zip"
New-Item -ItemType Directory -Force -Path $localProj | Out-Null

@'
{
  "name": "lab-playwright-m365-signin",
  "version": "1.0.0",
  "private": true,
  "description": "Playwright automation for M365/Entra sign-in telemetry in a lab",
  "scripts": {
    "test": "node run_playwright_office_login.js"
  },
  "dependencies": {
    "playwright": "^1.49.0"
  }
}
'@ | Set-Content -Path (Join-Path $localProj "package.json") -Encoding UTF8 -Force

@'
const { chromium } = require("playwright");
const fs = require("fs");
const path = require("path");

function nowTag() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}${pad(d.getMonth()+1)}${pad(d.getDate())}_${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
}

async function safeShot(page, outDir, name) {
  try { await page.screenshot({ path: path.join(outDir, name), fullPage: true }); } catch {}
}

(async () => {
  const url  = process.env.PORTAL_URL || "https://portal.office.com";
  const user = process.env.PORTAL_USERNAME;
  const pass = process.env.PORTAL_PASSWORD;

  if (!user || !pass) {
    console.error("Missing env vars PORTAL_USERNAME / PORTAL_PASSWORD.");
    process.exit(2);
  }

  const outDir = process.env.PW_OUTDIR || "C:\\AtomicRedTeam\\Logs";
  try { fs.mkdirSync(outDir, { recursive: true }); } catch {}

  const tag = nowTag();
  const browser = await chromium.launch({ headless: false, args: ["--start-maximized"] });
  const context = await browser.newContext({ viewport: null });
  const page = await context.newPage();

  console.log(`Go to ${url}`);
  await page.goto(url, { waitUntil: "domcontentloaded", timeout: 120000 });
  await page.waitForTimeout(1500);
  await safeShot(page, outDir, `pw_${tag}_01_landing.png`);

  const loginBox = page.locator('input[name="loginfmt"], input[type="email"]').first();
  await loginBox.waitFor({ timeout: 60000 });
  await loginBox.fill(user);
  await safeShot(page, outDir, `pw_${tag}_02_user_filled.png`);

  const nextBtn = page.locator('#idSIButton9, input[type="submit"], button[type="submit"]').first();
  await nextBtn.click({ timeout: 15000 });
  await page.waitForTimeout(1500);
  await safeShot(page, outDir, `pw_${tag}_03_after_next.png`);

  const passBox = page.locator('input[name="passwd"], input[type="password"]').first();
  await passBox.waitFor({ timeout: 60000 });
  await passBox.fill(pass);
  await safeShot(page, outDir, `pw_${tag}_04_pass_filled.png`);

  const signinBtn = page.locator('#idSIButton9, input[type="submit"], button[type="submit"]').first();
  await signinBtn.click({ timeout: 15000 });
  await page.waitForTimeout(2500);
  await safeShot(page, outDir, `pw_${tag}_05_after_signin.png`);

  const stayText = page.locator('text=Stay signed in').first();
  const stayNo   = page.locator('#idBtn_Back').first();
  const stayYes  = page.locator('#idSIButton9').first();

  if (await stayText.count()) {
    if (await stayNo.count()) {
      console.log("Stay signed in prompt -> clicking No");
      await stayNo.click({ timeout: 10000 });
    } else if (await stayYes.count()) {
      console.log("Stay signed in prompt -> clicking Yes");
      await stayYes.click({ timeout: 10000 });
    }
    await page.waitForTimeout(2000);
    await safeShot(page, outDir, `pw_${tag}_06_stay_response.png`);
  }

  await page.waitForTimeout(6000);
  await safeShot(page, outDir, `pw_${tag}_07_final.png`);

  console.log("Done.");
  await context.close();
  await browser.close();
  process.exit(0);
})();
'@ | Set-Content -Path (Join-Path $localProj "run_playwright_office_login.js") -Encoding UTF8 -Force

if (Test-Path $localZip) { Remove-Item $localZip -Force }
Compress-Archive -Path (Join-Path $localProj "*") -DestinationPath $localZip -Force
Write-Host "Payload zip: $localZip"
Write-Host ""

# =======================================
# 2) RUNNER SCRIPT (DEPLOYED TO ENDPOINTS)
# =======================================
$RunnerContent = @'
param(
  [Parameter(Mandatory=$true)][string]$PortalUrl,
  [Parameter(Mandatory=$true)][string]$Username,
  [Parameter(Mandatory=$true)][string]$Password
)

$ErrorActionPreference = "Stop"

$Root   = "C:\AtomicRedTeam"
$PWDir  = Join-Path $Root "Playwright"
$LogDir = Join-Path $Root "Logs"
New-Item -ItemType Directory -Force -Path $PWDir, $LogDir | Out-Null

$ts  = Get-Date -Format "yyyyMMdd_HHmmss"
$log = Join-Path $LogDir "playwright_$($env:COMPUTERNAME)_$ts.log"

function Log($m) { ("[{0}] {1}" -f (Get-Date), $m) | Tee-Object -FilePath $log -Append | Out-Null }

$lockPath = Join-Path $Root "pw_run.lock"
$lockHandle = $null

try {
  Log "Starting Playwright runner. Username=$Username PortalUrl=$PortalUrl"

  $node = Get-Command node.exe -ErrorAction SilentlyContinue
  $npm  = Get-Command npm.cmd  -ErrorAction SilentlyContinue
  if (-not $node) { Log "ERROR: node.exe not found in PATH."; exit 2 }
  if (-not $npm)  { Log "ERROR: npm.cmd not found in PATH.";  exit 3 }

  if (-not (Test-Path (Join-Path $PWDir "package.json"))) { Log "ERROR: package.json not found under $PWDir."; exit 4 }

  for ($i=0; $i -lt 30; $i++) {
    try { $lockHandle = [System.IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None'); break }
    catch { Start-Sleep -Seconds 2 }
  }
  if (-not $lockHandle) { Log "ERROR: Could not acquire lock."; exit 5 }

  Push-Location $PWDir

  if (-not (Test-Path (Join-Path $PWDir "node_modules"))) {
    Log "node_modules missing -> npm install (requires internet)"
    & $npm.Source install 2>&1 | Tee-Object -FilePath $log -Append | Out-Null
  }

  $marker = Join-Path $PWDir ".pw_browsers_installed"
  if (-not (Test-Path $marker)) {
    Log "Installing Playwright browsers (first time)"
    & $npm.Source exec playwright install 2>&1 | Tee-Object -FilePath $log -Append | Out-Null
    New-Item -ItemType File -Force -Path $marker | Out-Null
  }

  $env:PORTAL_URL      = $PortalUrl
  $env:PORTAL_USERNAME = $Username
  $env:PORTAL_PASSWORD = $Password
  $env:PW_OUTDIR       = $LogDir

  Log "Running: npm test"
  & $npm.Source test 2>&1 | Tee-Object -FilePath $log -Append | Out-Null
  Log "Completed Playwright run."
}
catch {
  Log ("ERROR: " + $_.Exception.Message)
  throw
}
finally {
  try { Pop-Location } catch {}
  try { if ($lockHandle) { $lockHandle.Close(); $lockHandle.Dispose() } } catch {}
}
'@

function Ensure-RemoteFoldersAndRunner {
  param([string]$Computer)

  Invoke-Command -ComputerName $Computer -ScriptBlock {
    param($RemoteRoot, $RemotePWDir, $RemoteLogs, $RunnerPath, $RunnerContent)
    New-Item -ItemType Directory -Force -Path $RemoteRoot, $RemotePWDir, $RemoteLogs | Out-Null
    Set-Content -Path $RunnerPath -Value $RunnerContent -Encoding UTF8 -Force
  } -ArgumentList $RemoteRoot, $RemotePWDir, $RemoteLogs, $RunnerPath, $RunnerContent
}

function Push-PlaywrightZip {
  param(
    [string]$Computer,
    [string]$ZipPath,
    [string]$DestDir
  )

  # Use PS Remoting session to avoid \\C$ path issues
  $session = New-PSSession -ComputerName $Computer

  try {
    Invoke-Command -Session $session -ScriptBlock {
      param($DestDir)
      New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
      New-Item -ItemType Directory -Force -Path "C:\Temp" | Out-Null
    } -ArgumentList $DestDir

    $remoteZipLocal = "C:\Temp\PlaywrightPayload.zip"
    Copy-Item -ToSession $session -Path $ZipPath -Destination $remoteZipLocal -Force

    Invoke-Command -Session $session -ScriptBlock {
      param($remoteZipLocal, $DestDir)

      # clear old content
      Get-ChildItem -Path $DestDir -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

      Expand-Archive -Path $remoteZipLocal -DestinationPath $DestDir -Force
      Remove-Item $remoteZipLocal -Force
    } -ArgumentList $remoteZipLocal, $DestDir
  }
  finally {
    if ($session) { Remove-PSSession $session }
  }
}

function Register-PlaywrightScheduledTask {
  param(
    [string]$Computer,
    [string]$TaskName,
    [string]$DomainUser,
    [string]$PortalUrl,
    [string]$Username,
    [string]$Password
  )

  $args = @(
    "-NoProfile",
    "-ExecutionPolicy Bypass",
    "-File `"$RunnerPath`"",
    "-PortalUrl `"$PortalUrl`"",
    "-Username `"$Username`"",
    "-Password `"$Password`""
  ) -join " "

  Invoke-Command -ComputerName $Computer -ScriptBlock {
    param($TaskName, $DomainUser, $ArgsString)

    $action    = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $ArgsString
    $trigger   = New-ScheduledTaskTrigger -AtLogOn -User $DomainUser
    $principal = New-ScheduledTaskPrincipal -UserId $DomainUser -LogonType Interactive -RunLevel Highest

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
  } -ArgumentList $TaskName, $DomainUser, $args
}

# =====================
# EXECUTION
# =====================
$byComputer = $Assignments | Group-Object Computer

foreach ($group in $byComputer) {
  $computer = $group.Name
  Write-Host "=== $computer ==="

  try {
    Test-WSMan -ComputerName $computer -ErrorAction Stop | Out-Null

    Ensure-RemoteFoldersAndRunner -Computer $computer
    Write-Host "  [+] Runner deployed"

    Push-PlaywrightZip -Computer $computer -ZipPath $localZip -DestDir $RemotePWDir
    Write-Host "  [+] Playwright payload pushed"

    foreach ($a in $group.Group) {
      $userSam = $a.UserSam
      $forceLabAdmin = ($null -ne $a.ForceLabAdmin -and [bool]$a.ForceLabAdmin)

      if ($computer -ieq "CLIENT4" -and $forceLabAdmin) {
        $taskUser = "$DomainNetbios\labadmin"
        $taskName = "PlaywrightCampaign-labadmin"
        $uName    = "$DomainNetbios\labadmin"
        $uPass    = $LabAdminPassword
      } else {
        $taskUser = "$DomainNetbios\$userSam"
        $taskName = "PlaywrightCampaign-$userSam"
        $uName    = "$DomainNetbios\$userSam"
        $uPass    = $DefaultUserPassword
      }

      Register-PlaywrightScheduledTask -Computer $computer -TaskName $taskName -DomainUser $taskUser -PortalUrl $PortalUrl -Username $uName -Password $uPass
      Write-Host "  [+] Task created: $taskName ($taskUser)"
    }

    Invoke-Command -ComputerName $computer -ScriptBlock {
      Get-ScheduledTask | Where-Object { $_.TaskName -like "PlaywrightCampaign-*" } | Select-Object TaskName, State
    } | ForEach-Object {
      Write-Host ("      -> {0} [{1}]" -f $_.TaskName, $_.State)
    }
  }
  catch {
    Write-Warning ("  [!] Failed on {0}: {1}" -f $computer, $_.Exception.Message)
  }

  Write-Host ""
}

Write-Host "Done. Log on as each user so the AtLogOn tasks fire."
Write-Host "Logs/screenshots will be in: C:\AtomicRedTeam\Logs"
