<#
UserSim_MasterBootstrap.ps1
------------------------------------------------------------
Enterprise User Activity Simulation Framework (Persona-Based)

This script deploys and schedules recurring simulated user activity
across Windows endpoints to generate realistic behavioral telemetry
for security research, detection engineering validation, and
autonomous response testing.

The framework creates persona-driven workloads that emulate
differentiated user behavior patterns (e.g., light, office, noisy)
by executing periodic activity cycles that include:

    • Automated web browsing using Playwright (headless Chromium)
    • File system interaction (creation, modification, downloads)
    • Randomized timing, navigation, and interaction patterns
    • Continuous recurring execution via scheduled tasks

Each activity cycle runs under the security context of real domain
user accounts and executes at configurable intervals to produce
persistent, multi-user enterprise telemetry.

The script automatically:
    • Detects the local machine identity
    • Maps assigned users and personas to that endpoint
    • Deploys required simulation scripts and runtime components
    • Configures required Windows privileges (batch logon)
    • Creates scheduled tasks for each persona workload
    • Optionally performs an immediate warm-up execution

Primary Purpose
------------------------------------------------------------
This tool is intended for controlled lab environments to support:

    • Behavioral baseline generation
    • Detection threshold testing
    • Identity-driven telemetry production
    • Autonomous security response evaluation
    • Multi-user workload simulation
    • Adversarial response research (e.g., ADID / self-denial scenarios)

Execution Model
------------------------------------------------------------
Each scheduled task executes a repeating activity cycle that invokes:

    run-cycle.ps1
        ├─ simulate-files.ps1   (file system activity)
        └─ simulate-web.js      (web browsing automation)

Activity intensity and frequency are determined by persona type.

Environment Requirements
------------------------------------------------------------
    • Windows endpoints (domain-joined recommended)
    • Node.js and npm installed
    • Internet connectivity (for Playwright browser installation)
    • Administrative privileges to create scheduled tasks
    • Lab or research environment (not production)

Security Notice
------------------------------------------------------------
This framework stores and uses credentials to execute scheduled tasks.
It is designed strictly for isolated research and testing environments.
Do NOT deploy in production systems.

Author Intent
------------------------------------------------------------
Provides controlled, repeatable user-behavior simulation for security
instrumentation, telemetry generation, and defensive response analysis.

------------------------------------------------------------
#>

#requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

# =========================
# EDIT ONLY THIS SECTION
# =========================
$DomainNetbios = "KIDSREADINGROAD"
$DefaultPasswordPlain = "P@ssw0rd123!"
$RunEveryMinutes = 20
$DoWarmupRun = $true   # set $false if you don't want immediate task runs

# Map: per machine -> users + persona
# CHANGE the users for client2 and client3 here.
$MachineUserMap = @{
  "CLIENT1" = @(
    @{ Sam="bhernandez"; Persona="light"  },
    @{ Sam="cdavis";     Persona="office" },
    @{ Sam="ddavis";     Persona="office" },
    @{ Sam="ebrown";     Persona="office" },
    @{ Sam="jmartinez";  Persona="noisy"  }
  )

  # Example placeholders — replace with your real assignments
  "CLIENT2" = @(
    @{ Sam="jmiller";    Persona="office" },
    @{ Sam="sbrown";     Persona="light"  },
    @{ Sam="swilson";    Persona="office" },
    @{ Sam="twilson";    Persona="noisy"  },
    @{ Sam="twilliams";  Persona="office" }
  )

  "CLIENT3" = @(
    @{ Sam="plopez";     Persona="office" },
    @{ Sam="krodriguez"; Persona="noisy"  },
    @{ Sam="rwilson";    Persona="light"  },
    @{ Sam="wanderson";  Persona="office" }
  )
}

# Sites to visit
$Sites = @(
  "https://www.yahoo.com",
  "https://www.espn.com",
  "https://www.foxnews.com",
  "https://kidsreadingroad.com",
  "https://www.weather.com",
  "https://en.wikipedia.org/wiki/Main_Page",
  "https://www.reuters.com"
)

# =========================
# END EDIT SECTION
# =========================

# Paths
$BaseDir   = "C:\UserSim"
$LogsDir   = Join-Path $BaseDir "Logs"
$UsersCsv  = Join-Path $BaseDir "users.csv"
$BatchGroup = "UserSimBatch"
$TaskRoot  = "\UserSim\"
$BrowserDir = Join-Path $BaseDir "pw-browsers"

function Require-Command([string]$Name) {
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required command not found in PATH: $Name"
  }
}

function Write-FileUtf8NoBom([string]$Path, [string]$Content) {
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Run-Cmd([string]$CmdLine) {
  Write-Host ">> $CmdLine"
  $p = Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $CmdLine -Wait -PassThru -NoNewWindow
  if ($p.ExitCode -ne 0) { throw "Command failed (exit $($p.ExitCode)): $CmdLine" }
}

# -------------------------
# Determine machine name
# -------------------------
$ComputerName = $env:COMPUTERNAME.ToUpperInvariant()
Write-Host "=== UserSim Master Bootstrap ==="
Write-Host "Machine: $ComputerName"

if (-not $MachineUserMap.ContainsKey($ComputerName)) {
  $known = ($MachineUserMap.Keys | Sort-Object) -join ", "
  throw "No user mapping found for machine '$ComputerName'. Edit `$MachineUserMap. Known: $known"
}

$AssignedUsers = $MachineUserMap[$ComputerName]
if (-not $AssignedUsers -or $AssignedUsers.Count -lt 1) {
  throw "AssignedUsers list is empty for $ComputerName"
}

# -------------------------
# Create base folders
# -------------------------
New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null
New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null
New-Item -ItemType Directory -Path $BrowserDir -Force | Out-Null

# Permissions: allow Users to write logs + browser cache
icacls $BaseDir /grant "Users:(OI)(CI)M" /T | Out-Null
icacls $BrowserDir /grant "Users:(OI)(CI)M" /T | Out-Null

# -------------------------
# Write users.csv
# -------------------------
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("SamAccountName,Password,Persona") | Out-Null
foreach ($u in $AssignedUsers) {
  $lines.Add("$($u.Sam),$DefaultPasswordPlain,$($u.Persona)") | Out-Null
}
Write-FileUtf8NoBom -Path $UsersCsv -Content ($lines -join "`r`n")
Write-Host "✅ Wrote $UsersCsv"

# -------------------------
# Preflight Node/NPM
# -------------------------
Require-Command "node"
Require-Command "npm"
Require-Command "npx"

# -------------------------
# Write simulate-files.ps1
# -------------------------
$simulateFilesPs1 = @'
param(
  [ValidateSet("light","office","noisy")]
  [string]$Persona = "office",
  [string]$LogPath = "C:\UserSim\Logs\files.log"
)
function Get-Rand($min,$max){ Get-Random -Minimum $min -Maximum ($max+1) }
$docRoot = Join-Path $env:USERPROFILE "Documents\UserSim"
$dlRoot  = Join-Path $env:USERPROFILE "Downloads"
New-Item -ItemType Directory -Path $docRoot -Force | Out-Null
$topics = @(
  "thesis notes","meeting recap","budget draft","travel plan","security ideas",
  "incident notes","to-do list","kids reading plan","project outline","random notes"
)
switch ($Persona) {
  "light"  { $newFiles = Get-Rand 1 2;  $editFiles = Get-Rand 0 2;  $downloadMarkers = Get-Rand 0 1 }
  "office" { $newFiles = Get-Rand 2 5;  $editFiles = Get-Rand 1 4;  $downloadMarkers = Get-Rand 1 2 }
  "noisy"  { $newFiles = Get-Rand 5 10; $editFiles = Get-Rand 4 10; $downloadMarkers = Get-Rand 2 4 }
}
$now = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
Add-Content -Path $LogPath -Value "$now [$env:USERNAME] Persona=$Persona Start simulate-files"
1..$newFiles | ForEach-Object {
  $stamp = Get-Date
  $fn  = "notes_{0:yyyyMMdd_HHmmss}_{1}.txt" -f $stamp, (Get-Random -Minimum 1000 -Maximum 9999)
  $fp  = Join-Path $docRoot $fn
  $body = @"
Title: $(Get-Random $topics)
User:  $env:USERNAME
Time:  $stamp
- Item $(Get-Rand 1 99)
- Item $(Get-Rand 1 99)
- Item $(Get-Rand 1 99)
"@
  Set-Content -Path $fp -Value $body -Encoding UTF8
}
$existing = Get-ChildItem -Path $docRoot -Filter "*.txt" -ErrorAction SilentlyContinue
if ($existing) {
  1..$editFiles | ForEach-Object {
    $f = Get-Random $existing
    Add-Content -Path $f.FullName -Value ("{0} - appended line {1}" -f (Get-Date), (Get-Rand 1 9999))
  }
}
1..$downloadMarkers | ForEach-Object {
  $stamp = Get-Date
  $fp = Join-Path $dlRoot ("UserSim_download_{0:yyyyMMdd_HHmmss}_{1}.txt" -f $stamp, (Get-Random -Minimum 100 -Maximum 999))
  Set-Content -Path $fp -Value "simulated download marker: $stamp" -Encoding UTF8
}
$now2 = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
Add-Content -Path $LogPath -Value "$now2 [$env:USERNAME] Persona=$Persona End simulate-files"
'@
Write-FileUtf8NoBom -Path (Join-Path $BaseDir "simulate-files.ps1") -Content $simulateFilesPs1

# -------------------------
# Write simulate-web.js (persona-aware by env var)
# -------------------------
$sitesJson = ($Sites | ConvertTo-Json -Compress)
$simulateWebJs = @"
const { chromium } = require('playwright');

const sites = $sitesJson;

function rand(min, max) { return Math.floor(Math.random() * (max - min + 1)) + min; }
function pick(arr) { return arr[rand(0, arr.length - 1)]; }
function chance(p) { return Math.random() < p; }

const persona = (process.env.USERSIM_PERSONA || 'office').toLowerCase();

const profiles = {
  light:  { visitsMin: 2,  visitsMax: 4,  scrollMin: 1, scrollMax: 3,  clickChance: 0.25, pauseMinMs: 2500, pauseMaxMs: 7000 },
  office: { visitsMin: 3,  visitsMax: 7,  scrollMin: 2, scrollMax: 6,  clickChance: 0.45, pauseMinMs: 2500, pauseMaxMs: 9000 },
  noisy:  { visitsMin: 6,  visitsMax: 12, scrollMin: 4, scrollMax: 10, clickChance: 0.65, pauseMinMs: 1500, pauseMaxMs: 6000 }
};
const cfg = profiles[persona] || profiles.office;

(async () => {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 1366, height: 768 },
    userAgent:
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
      "(KHTML, like Gecko) Chrome/120 Safari/537.36"
  });

  const page = await context.newPage();
  const visits = rand(cfg.visitsMin, cfg.visitsMax);

  for (let i = 0; i < visits; i++) {
    const url = pick(sites);
    try {
      await page.goto(url, { waitUntil: "domcontentloaded", timeout: 60000 });
      await page.waitForTimeout(rand(cfg.pauseMinMs, cfg.pauseMaxMs));

      const scrolls = rand(cfg.scrollMin, cfg.scrollMax);
      for (let s = 0; s < scrolls; s++) {
        await page.mouse.wheel(0, rand(400, 1600));
        await page.waitForTimeout(rand(600, 2200));
      }

      if (chance(cfg.clickChance)) {
        const links = await page.locator("a:visible").all();
        if (links.length > 0) {
          const idx = rand(0, Math.min(links.length - 1, 30));
          try { await links[idx].click({ timeout: 3000 }); } catch {}
          await page.waitForTimeout(rand(1200, 6000));
        }
      }
    } catch {
      // ignore and continue
    }
  }

  await context.close();
  await browser.close();
})();
"@
Write-FileUtf8NoBom -Path (Join-Path $BaseDir "simulate-web.js") -Content $simulateWebJs

# -------------------------
# Write run-cycle.ps1 (robust logging + web stdout/err capture + shared browsers path)
# -------------------------
$runCyclePs1 = @'
param(
  [ValidateSet("light","office","noisy")]
  [string]$Persona = "office"
)
$ErrorActionPreference = "Stop"

$logDir = "C:\UserSim\Logs"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$log = Join-Path $logDir ("cycle_{0}.log" -f $env:USERNAME)

function Log([string]$msg) {
  $ts = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
  Add-Content -Path $log -Value "$ts [$env:USERNAME] $msg"
}

Log "START persona=$Persona"

try {
  Log "STEP files: begin"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\UserSim\simulate-files.ps1 -Persona $Persona -LogPath $log
  Log "STEP files: end"
} catch {
  Log ("ERROR files: " + $_.Exception.Message)
}

try {
  Log "STEP web: begin"
  cmd.exe /c "set PLAYWRIGHT_BROWSERS_PATH=C:\UserSim\pw-browsers && set USERSIM_PERSONA=$Persona && cd /d C:\UserSim && node simulate-web.js 1>>C:\UserSim\Logs\web_%USERNAME%.out 2>>C:\UserSim\Logs\web_%USERNAME%.err"
  Log ("STEP web: end exitcode=" + $LASTEXITCODE)
} catch {
  Log ("ERROR web: " + $_.Exception.Message)
}

Log "END persona=$Persona"
'@
Write-FileUtf8NoBom -Path (Join-Path $BaseDir "run-cycle.ps1") -Content $runCyclePs1

# -------------------------
# Install Playwright + browsers (shared browsers path)
# -------------------------
if (-not (Test-Path (Join-Path $BaseDir "package.json"))) {
  Run-Cmd "cd /d `"$BaseDir`" && npm init -y"
}
Run-Cmd "cd /d `"$BaseDir`" && npm install playwright"
Run-Cmd "cd /d `"$BaseDir`" && set PLAYWRIGHT_BROWSERS_PATH=$BrowserDir && npx playwright install"
Write-Host "✅ Playwright installed + browsers in $BrowserDir"

# -------------------------
# Ensure UserSimBatch group + add users
# -------------------------
if (-not (Get-LocalGroup -Name $BatchGroup -ErrorAction SilentlyContinue)) {
  New-LocalGroup -Name $BatchGroup -Description "UserSim batch task users" | Out-Null
  Write-Host "✅ Created local group: $BatchGroup"
}

foreach ($u in $AssignedUsers) {
  $member = "$DomainNetbios\$($u.Sam)"
  try {
    Add-LocalGroupMember -Group $BatchGroup -Member $member -ErrorAction Stop
    Write-Host "✅ Added to ${BatchGroup}: $member"
  } catch {
    if ($_.Exception.Message -match "already a member") {
      Write-Host "ℹ️ Already in ${BatchGroup}: $member"
    } else {
      throw
    }
  }
}

# -------------------------
# Grant SeBatchLogonRight (PS5-safe secedit approach)
# -------------------------
$temp = Join-Path $env:TEMP "usersim_secpol"
New-Item -ItemType Directory -Path $temp -Force | Out-Null
$cfg = Join-Path $temp "secpol.cfg"
$inf = Join-Path $temp "grant_batch.inf"
$db  = Join-Path $temp "secpol.sdb"

secedit /export /cfg $cfg | Out-Null

$groupSid = (Get-LocalGroup -Name $BatchGroup).SID.Value
Write-Host "Batch group SID: $groupSid"

$cfgText = Get-Content $cfg -Raw
if ($cfgText -notmatch '(?im)^\[Privilege Rights\]\s*$') {
  $cfgText += "`r`n[Privilege Rights]`r`n"
}

$match = Select-String -InputObject $cfgText -Pattern '(?im)^SeBatchLogonRight\s*=\s*(.*)$'
if ($match) {
  $current = $match.Matches[0].Groups[1].Value.Trim()
  if ($current -notmatch [regex]::Escape($groupSid)) {
    $new = if ([string]::IsNullOrWhiteSpace($current)) { "*$groupSid" } else { "$current,*$groupSid" }
    $cfgText = [regex]::Replace($cfgText, '(?im)^SeBatchLogonRight\s*=.*$', "SeBatchLogonRight = $new")
    Write-Host "✅ Appended batch right"
  } else {
    Write-Host "ℹ️ Batch right already present"
  }
} else {
  $cfgText = [regex]::Replace(
    $cfgText,
    '(?im)^\[Privilege Rights\]\s*$',
    "[Privilege Rights]`r`nSeBatchLogonRight = *$groupSid"
  )
  Write-Host "✅ Added batch right"
}

@"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[Privilege Rights]
"@ | Out-File -FilePath $inf -Encoding Unicode

($cfgText -split "`r?`n" | Where-Object { $_ -match '^(Se\S+)\s*=' }) |
  Out-File -FilePath $inf -Append -Encoding Unicode

secedit /configure /db $db /cfg $inf /areas USER_RIGHTS | Out-Null
gpupdate /force | Out-Null
Write-Host "✅ Granted SeBatchLogonRight to $BatchGroup"

# -------------------------
# Create scheduled tasks
# -------------------------
$csvUsers = Import-Csv $UsersCsv
$offset = 0

foreach ($u in $csvUsers) {
  $sam = $u.SamAccountName
  $pw  = $u.Password
  $persona = if ($u.Persona) { $u.Persona } else { "office" }

  $runAs = "$DomainNetbios\$sam"
  $taskName = "$TaskRoot$sam-Cycle"
  $start = (Get-Date).AddMinutes($offset)
  $st = $start.ToString("HH:mm")
  $offset++

  $tr = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\UserSim\run-cycle.ps1 -Persona $persona"

  Write-Host "Creating task $taskName as $runAs (persona=$persona)"
  schtasks /Create /TN $taskName /TR $tr /SC MINUTE /MO $RunEveryMinutes /ST $st /RU $runAs /RP $pw /RL HIGHEST /F | Out-Host
}

Write-Host "`n✅ Tasks created under $TaskRoot"

# -------------------------
# Warm-up run (optional)
# -------------------------
if ($DoWarmupRun) {
  foreach ($u in $AssignedUsers) {
    $tn = "$TaskRoot$($u.Sam)-Cycle"
    Write-Host "Warmup run: $tn"
    schtasks /Run /TN $tn | Out-Null
  }
  Write-Host "✅ Warmup triggered (check logs within 1-2 minutes)"
}

Write-Host "`nDONE."
Write-Host "Verify: schtasks /Query /TN `"\UserSim`" /V /FO LIST | findstr /i `"TaskName Last Result`""
Write-Host "Logs:   C:\UserSim\Logs"
