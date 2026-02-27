Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# =========================
# UserSim Bootstrap - client1
# =========================
$ErrorActionPreference = "Stop"

$BaseDir = "C:\UserSim"
$LogsDir = Join-Path $BaseDir "Logs"
$DomainNetbios = "KIDSREADINGROAD"
$DefaultPasswordPlain = "P@ssw0rd123!"
$RunEveryMinutes = 20

# client1 assignments (5 users)
$AssignedUsers = @(
    @{ Sam="bhernandez"; Persona="light"  },
    @{ Sam="cdavis";     Persona="office" },
    @{ Sam="ddavis";     Persona="office" },
    @{ Sam="ebrown";     Persona="office" },
    @{ Sam="jmartinez";  Persona="noisy"  }
)

$Sites = @(
  "https://www.yahoo.com",
  "https://www.espn.com",
  "https://www.foxnews.com",
  "https://kidsreadingroad.com",
  "https://www.weather.com",
  "https://en.wikipedia.org/wiki/Main_Page",
  "https://www.reuters.com"
)

function Write-FileUtf8NoBom([string]$Path, [string]$Content) {
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Require-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command not found in PATH: $Name. Install it or add to PATH and rerun."
    }
}

function Run-Cmd([string]$CmdLine) {
    Write-Host ">> $CmdLine"
    $p = Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $CmdLine -Wait -PassThru -WindowStyle Hidden
    if ($p.ExitCode -ne 0) { throw "Command failed (exit $($p.ExitCode)): $CmdLine" }
}

Write-Host "=== Bootstrapping UserSim on client1 ==="

Require-Command "node"
Require-Command "npm"
Require-Command "npx"

New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null
New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null

# 1) Create users.csv (no need to pre-stage anything)
$usersCsvPath = Join-Path $BaseDir "users.csv"
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("SamAccountName,Password,Persona") | Out-Null
foreach ($u in $AssignedUsers) {
    $lines.Add("$($u.Sam),$DefaultPasswordPlain,$($u.Persona)") | Out-Null
}
Write-FileUtf8NoBom -Path $usersCsvPath -Content ($lines -join "`r`n")
Write-Host "Created: $usersCsvPath"

# 2) simulate-files.ps1
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
  "light"  { $newFiles = Get-Rand 1 2; $editFiles = Get-Rand 0 2; $downloadMarkers = Get-Rand 0 1 }
  "office" { $newFiles = Get-Rand 2 5; $editFiles = Get-Rand 1 4; $downloadMarkers = Get-Rand 1 2 }
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

# 3) simulate-web.js
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
    } catch {}
  }
  await context.close();
  await browser.close();
})();
"@
Write-FileUtf8NoBom -Path (Join-Path $BaseDir "simulate-web.js") -Content $simulateWebJs

# 4) run-cycle.ps1
$runCyclePs1 = @'
$ErrorActionPreference = "Stop"
$persona = $env:USERSIM_PERSONA
if (-not $persona) { $persona = "office" }
$logDir = "C:\UserSim\Logs"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$log = Join-Path $logDir ("cycle_{0}.log" -f $env:USERNAME)
$ts = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
Add-Content -Path $log -Value "$ts [$env:USERNAME] START persona=$persona"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\UserSim\simulate-files.ps1 -Persona $persona -LogPath $log
cmd.exe /c "cd /d C:\UserSim && set USERSIM_PERSONA=%USERSIM_PERSONA% && node simulate-web.js" | Out-Null
$ts2 = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
Add-Content -Path $log -Value "$ts2 [$env:USERNAME] END persona=$persona"
'@
Write-FileUtf8NoBom -Path (Join-Path $BaseDir "run-cycle.ps1") -Content $runCyclePs1

# 5) Install Playwright + browsers
if (-not (Test-Path (Join-Path $BaseDir "package.json"))) {
    Run-Cmd "cd /d `"$BaseDir`" && npm init -y"
}
Run-Cmd "cd /d `"$BaseDir`" && npm install playwright"
Run-Cmd "cd /d `"$BaseDir`" && npx playwright install"
Write-Host "✅ Playwright installed."

# 6) Create Scheduled Tasks
$TaskRoot = "\UserSim\"
$csvUsers = Import-Csv $usersCsvPath
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

# (patched) skip schtasks delete; /F on create overwrites if needed
    Write-Host "Creating task $taskName as $runAs (persona=$persona, start=$st, every $RunEveryMinutes min)"
    schtasks /Create /TN $taskName /TR $tr /SC MINUTE /MO $RunEveryMinutes /ST $st /RU $runAs /RP $pw /RL HIGHEST /F | Out-Host
}

Write-Host "`n✅ DONE. Tasks created under \UserSim\"
Write-Host "Check tasks: schtasks /Query /TN `"\UserSim`" /FO LIST"
Write-Host "Test run:    schtasks /Run /TN `"\UserSim\bhernandez-Cycle`""
Write-Host "Logs in:     C:\UserSim\Logs"

