# ============================================================
# Script: Playwright Portal Automation Runner
#
# Description:
# Executes automated Playwright browser workflows for portal
# authentication and interaction using supplied credentials.
# The script prepares the runtime environment, validates Node.js
# and Playwright dependencies, installs required browsers, and
# ensures network readiness before execution.
#
# Designed for controlled lab environments to generate
# realistic user authentication activity and web interaction
# telemetry for hybrid enterprise security testing.
#
# Features:
# - Shared Playwright browser cache for consistency
# - Dependency validation and installation
# - Network and DNS readiness checks
# - Execution logging and success tracking
# - Concurrency locking to prevent overlapping runs
#
# Intended for research and lab simulation only.
# Not for production use.
# ============================================================
 
 param(
  [Parameter(Mandatory=$true)][string]$PortalUrl,
  [Parameter(Mandatory=$true)][string]$Username,
  [Parameter(Mandatory=$true)][string]$Password
)

$ErrorActionPreference = "Stop"

# PS7+: don't let native stderr behave like a terminating error record
if ($PSVersionTable.PSVersion.Major -ge 7) { $global:PSNativeCommandUseErrorActionPreference = $false }

$Root   = "C:\AtomicRedTeam"
$PWDir  = Join-Path $Root "Playwright"
$LogDir = Join-Path $Root "Logs"
New-Item -ItemType Directory -Force -Path $PWDir, $LogDir | Out-Null

# Force a shared browser cache so all users/machines behave consistently
$env:PLAYWRIGHT_BROWSERS_PATH = Join-Path $Root "PlaywrightBrowsers"
New-Item -ItemType Directory -Force -Path $env:PLAYWRIGHT_BROWSERS_PATH | Out-Null

$ts = (Get-Date).ToString("yyyyMMdd_HHmmss_fff") + "_pid$PID"
$log = Join-Path $LogDir "playwright_$($env:COMPUTERNAME)_$ts.log"
$successSentinel = Join-Path $LogDir "playwright_last_success.txt"

function Log($m) { ("[{0}
# --- PATCH: wait for DNS/network readiness ---
function Wait-NetworkReady {
  param(
    [string]$Host = "portal.office.com",
    [int]$TimeoutSeconds = 120
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    try {
      $dnsOk = $false
      try { [void][System.Net.Dns]::GetHostAddresses($Host); $dnsOk = $true } catch {}

      $tcpOk = $false
      try {
        $tnc = Test-NetConnection -ComputerName $Host -Port 443 -WarningAction SilentlyContinue
        $tcpOk = [bool]$tnc.TcpTestSucceeded
      } catch {}

      if ($dnsOk -and $tcpOk) { return $true }
    } catch {}

    Start-Sleep -Seconds 5
  }
  return $false
}
# --- END PATCH ---
] {1}" -f (Get-Date), $m) | Tee-Object -FilePath $log -Append | Out-Null }

function Run-Native {
  param(
    [Parameter(Mandatory=$true)][string]$File,
    [Parameter(Mandatory=$true)][string[]]$Args
  )

  $oldEap = $ErrorActionPreference
  $ErrorActionPreference = "Continue"   # prevent PS7 stderr -> terminating error
  try {
    Log "RUN: $File $($Args -join ' ')"
    & $File @Args 2>&1 | Tee-Object -FilePath $log -Append | Out-Null
    $code = $LASTEXITCODE
    if ($code -ne 0) {
      throw "Native command failed (exit $code): $File $($Args -join ' ')"
    }
  }
  finally {
    $ErrorActionPreference = $oldEap
  }
}

$lockPath = Join-Path $Root "pw_run.lock"
$lockHandle = $null

try {
  Log "Starting Playwright runner. Username=$Username PortalUrl=$PortalUrl"
  Log "PLAYWRIGHT_BROWSERS_PATH=$env:PLAYWRIGHT_BROWSERS_PATH"

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
    Run-Native -File $npm.Source -Args @("install","--no-fund","--no-audit","--loglevel=warn")
  }

  Log "Installing/validating Playwright browsers (shared cache)"
  Run-Native -File $npm.Source -Args @("exec","playwright","install")

  $env:PORTAL_URL      = $PortalUrl
  $env:PORTAL_USERNAME = $Username
  $env:PORTAL_PASSWORD = $Password
  $env:PW_OUTDIR       = $LogDir

  Log "Waiting for network readiness (DNS + TCP/443) to portal.office.com"
if (-not (Wait-NetworkReady -Host "portal.office.com" -TimeoutSeconds 180)) {
  throw "Network not ready: DNS/TCP check failed for portal.office.com"
}
Log "Running: npm test"Run-Native -File $npm.Source -Args @("test","--silent")

  Log "Completed Playwright run."

  # Write success sentinel
  $stamp = "[{0}] SUCCESS user={1} portal={2} browsersPath={3}" -f (Get-Date), $Username, $PortalUrl, $env:PLAYWRIGHT_BROWSERS_PATH
  Set-Content -Path $successSentinel -Value $stamp -Encoding UTF8 -Force
}
catch {
  Log ("ERROR: " + $_.Exception.Message)
  throw
}
finally {
  try { Pop-Location } catch {}
  try { if ($lockHandle) { $lockHandle.Close(); $lockHandle.Dispose() } } catch {}
}




