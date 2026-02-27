<#
Deploy-AtomicCampaign-MASTER.ps1 (Copy/paste-safe)

- Deploys runner to CLIENT1–4 via WinRM
- Creates per-user scheduled tasks on CLIENT1–3 (S4U, RunLevel Limited)
- Creates labadmin scheduled task on CLIENT4 (S4U, RunLevel Highest)
- Daily trigger + optional RunOnce trigger (default ON)

Runner outputs locally to C:\AtomicRedTeam\Results
#>

[CmdletBinding()]
param(
  [string]$DomainNetBIOS   = "KIDSREADINGROAD",
  [string]$RunnerLocalPath = "C:\AtomicRedTeam\Run-AtomicCampaign.ps1",
  [string]$TaskNamePrefix  = "AtomicCampaign",
  [ValidatePattern('^\d{2}:\d{2}$')]
  [string]$DailyTime       = "01:30",
  [bool]$AlsoRunOnceIn5Min = $true,

  [string]$AtomicRepo      = "C:\AtomicRedTeam\atomic-red-team",

  # Standard set (edit freely)
  [string[]]$Techniques    = @("T1059.001","T1047","T1105"),

  [string]$Client4Fqdn       = "CLIENT4.kidsreadingroad.com",
  [string]$LabAdminPrincipal = "KIDSREADINGROAD\labadmin",

  [string[]]$Computers = @(
    "CLIENT1.kidsreadingroad.com",
    "CLIENT2.kidsreadingroad.com",
    "CLIENT3.kidsreadingroad.com",
    "CLIENT4.kidsreadingroad.com"
  )
)

# ---------- USER↔MACHINE ASSIGNMENTS ----------
$Assignments = @(
  @{ Sam = "bhernandez"; Device = "CLIENT1.kidsreadingroad.com" },
  @{ Sam = "cdavis";     Device = "CLIENT1.kidsreadingroad.com" },
  @{ Sam = "ddavis";     Device = "CLIENT1.kidsreadingroad.com" },
  @{ Sam = "ebrown";     Device = "CLIENT1.kidsreadingroad.com" },
  @{ Sam = "jmartinez";  Device = "CLIENT1.kidsreadingroad.com" },
  @{ Sam = "jmiller";    Device = "CLIENT1.kidsreadingroad.com" },

  @{ Sam = "krodriguez"; Device = "CLIENT2.kidsreadingroad.com" },
  @{ Sam = "plopez";     Device = "CLIENT2.kidsreadingroad.com" },
  @{ Sam = "rwilson";    Device = "CLIENT2.kidsreadingroad.com" },
  @{ Sam = "sbrown";     Device = "CLIENT2.kidsreadingroad.com" },
  @{ Sam = "swilson";    Device = "CLIENT2.kidsreadingroad.com" },
  @{ Sam = "twilliams";  Device = "CLIENT2.kidsreadingroad.com" },

  @{ Sam = "twilson";    Device = "CLIENT3.kidsreadingroad.com" },
  @{ Sam = "wanderson";  Device = "CLIENT3.kidsreadingroad.com" },
  @{ Sam = "TestUser1";  Device = "CLIENT3.kidsreadingroad.com" },
  @{ Sam = "TestUser2";  Device = "CLIENT3.kidsreadingroad.com" },
  @{ Sam = "TestUser3";  Device = "CLIENT3.kidsreadingroad.com" },
  @{ Sam = "TestUser4";  Device = "CLIENT3.kidsreadingroad.com" }
)

# ---------- REMOTING CREDS ----------
$RemoteAdminCred = Get-Credential -Message "Enter ADMIN creds for WinRM to endpoints"

# ---------- BUILD RUNNER SCRIPT (DEPLOYED TO ENDPOINTS) ----------
$techList = ($Techniques | ForEach-Object { '"' + $_ + '"' }) -join ","

$runnerContent = @"
param(
  [string]`$ResultsRoot = "C:\AtomicRedTeam\Results",
  [string]`$AtomicRepo  = "$AtomicRepo",
  [string[]]`$Techniques = @($techList)
)

function Write-Log { param([string]`$m) Write-Host "[`$env:COMPUTERNAME] `$m" }

`$ts = Get-Date -Format "yyyyMMdd_HHmmss"
`$outDir = Join-Path `$ResultsRoot `$ts
New-Item -ItemType Directory -Force -Path `$outDir | Out-Null
Start-Transcript -Path (Join-Path `$outDir "transcript.txt") -Force | Out-Null

try {
  # Campaign markers for later correlation
  `$CampaignId = "AtomicCampaign_" + (Get-Date -Format "yyyyMMdd_HHmmss")
  `$UserUpn = (whoami /upn 2>`$null)
  if (-not `$UserUpn) { `$UserUpn = "`$env:USERDOMAIN\`$env:USERNAME" }

  "`$CampaignId`t`$UserUpn`t`$env:COMPUTERNAME`t`$(Get-Date -Format o)" |
    Out-File "C:\AtomicRedTeam\Results\campaign_marker.txt" -Append -Encoding utf8

  Write-Log "CampaignId: `$CampaignId"
  Write-Log "User: `$UserUpn"
  Write-Log "Output: `$outDir"

  Import-Module Invoke-AtomicRedTeam -Force -ErrorAction Stop

  `$atomicRoot  = `$AtomicRepo
  `$atomicsPath = Join-Path `$atomicRoot "atomics"

  if (-not (Test-Path `$atomicRoot))  { throw "Atomic repo not found at `$atomicRoot" }
  if (-not (Test-Path `$atomicsPath)) { throw "Atomics folder not found at `$atomicsPath" }

  # Scheduled-task safe: set both vars (and we will also pass -Path explicitly)
  `$env:ATOMIC_RED_TEAM_PATH = `$atomicRoot
  `$env:ATOMIC_RED_TEAM_DIR  = `$atomicRoot
  `$env:ATOMIC_RED_TEAM_DIR = `$AtomicRepo
  if (-not (Test-Path `$AtomicRepo)) { throw "Atomic repo not found at `$AtomicRepo" }

  # Defender (best effort)
  try { Get-MpComputerStatus | ConvertTo-Json -Depth 5 | Out-File (Join-Path `$outDir "defender_status.json") -Encoding utf8 } catch {}
  try {
    Get-MpThreatDetection | Select-Object * | Export-Csv (Join-Path `$outDir "defender_threat_detections.csv") -NoTypeInformation -Force
    Get-MpThreat | Select-Object * | Export-Csv (Join-Path `$outDir "defender_threats.csv") -NoTypeInformation -Force
  } catch {}

  # EVTX exports (best effort)
  `$logs = @(
    @{Name="Microsoft-Windows-Windows Defender/Operational"; File="defender_operational.evtx"},
    @{Name="Microsoft-Windows-PowerShell/Operational";       File="powershell_operational.evtx"},
    @{Name="Security";                                      File="security.evtx"}
  )
  if (Get-WinEvent -ListLog "Microsoft-Windows-Sysmon/Operational" -ErrorAction SilentlyContinue) {
    `$logs += @{Name="Microsoft-Windows-Sysmon/Operational"; File="sysmon_operational.evtx"}
  }
  foreach (`$l in `$logs) { try { wevtutil epl `$l.Name (Join-Path `$outDir `$l.File) /ow:true } catch {} }
  foreach (`$t in `$Techniques) {
    if ([string]::IsNullOrWhiteSpace(`$t)) {
      Write-Log "Skipping empty technique entry"
      continue
    }
    Write-Log "Running `$t"
    Invoke-AtomicTest `$t -Path `$atomicsPath -ErrorAction Continue *>&1 |
      Out-File (Join-Path `$outDir "atomic_`$t`_run.txt") -Append -Encoding utf8
  }

  `$zipPath = Join-Path `$ResultsRoot ("AtomicResults_{0}_{1}.zip" -f `$env:COMPUTERNAME, `$ts)
  if (Test-Path `$zipPath) { Remove-Item `$zipPath -Force -ErrorAction SilentlyContinue }
  Compress-Archive -Path (Join-Path `$outDir "*") -DestinationPath `$zipPath -Force
  Write-Log "ZIP: `$zipPath"
}
catch {
  Write-Log "ERROR: `$(`$_.Exception.Message)"
  `$_ | Out-String | Out-File (Join-Path `$outDir "error.txt") -Force -Encoding utf8
}
finally {
  Stop-Transcript | Out-Null
}
"@

$runnerBytes  = [System.Text.Encoding]::UTF8.GetBytes($runnerContent)
$client4Short = $Client4Fqdn.Split('.')[0]

# ---------- REMOTE DEPLOYMENT BLOCK ----------
$deployBlock = {
  param(
    [byte[]]$RunnerBytes,
    [string]$RunnerLocalPath,
    [string]$TaskNamePrefix,
    [string]$DomainNetBIOS,
    [string[]]$UsersForThisDevice,
    [string]$DailyTime,
    [bool]$AlsoRunOnceIn5Min,
    [string]$Client4ShortName,
    [string]$LabAdminPrincipal
  )

  function Log($m){ Write-Host "[$env:COMPUTERNAME] $m" }

  # Drop runner
  $dir = Split-Path $RunnerLocalPath -Parent
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  [IO.File]::WriteAllBytes($RunnerLocalPath, $RunnerBytes)
  Log "Runner deployed to $RunnerLocalPath"

  $count = if ($UsersForThisDevice) { $UsersForThisDevice.Count } else { 0 }
  Log "Received $count user(s): $($UsersForThisDevice -join ', ')"

  $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$RunnerLocalPath`""

  $triggers = @()
  $triggers += New-ScheduledTaskTrigger -Daily -At ([datetime]::ParseExact($DailyTime,'HH:mm',$null))
  if ($AlsoRunOnceIn5Min) { $triggers += New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(5)) }

  $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

  $out = @()

  foreach ($u in ($UsersForThisDevice | Where-Object { $_ -and $_.Trim() })) {
    $userId   = "$DomainNetBIOS\$u"
    $taskName = "$TaskNamePrefix-$u"
    try {
      $principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Limited
      $task = New-ScheduledTask -Action $action -Trigger $triggers -Principal $principal -Settings $settings
      Register-ScheduledTask -TaskName $taskName -InputObject $task -Force -ErrorAction Stop | Out-Null
      $nrt = (Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction Stop).NextRunTime
      $out += [pscustomobject]@{ Computer=$env:COMPUTERNAME; TaskName=$taskName; RunAs=$userId; NextRunTime=$nrt; Status="OK" }
    } catch {
      $out += [pscustomobject]@{ Computer=$env:COMPUTERNAME; TaskName=$taskName; RunAs=$userId; NextRunTime=$null; Status="FAIL"; Error=$_.Exception.Message }
    }
  }

  if ($env:COMPUTERNAME -ieq $Client4ShortName) {
    $taskName = "$TaskNamePrefix-labadmin"
    try {
      $principal = New-ScheduledTaskPrincipal -UserId $LabAdminPrincipal -LogonType S4U -RunLevel Highest
      $task = New-ScheduledTask -Action $action -Trigger $triggers -Principal $principal -Settings $settings
      Register-ScheduledTask -TaskName $taskName -InputObject $task -Force -ErrorAction Stop | Out-Null
      $nrt = (Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction Stop).NextRunTime
      $out += [pscustomobject]@{ Computer=$env:COMPUTERNAME; TaskName=$taskName; RunAs=$LabAdminPrincipal; NextRunTime=$nrt; Status="OK" }
    } catch {
      $out += [pscustomobject]@{ Computer=$env:COMPUTERNAME; TaskName=$taskName; RunAs=$LabAdminPrincipal; NextRunTime=$null; Status="FAIL"; Error=$_.Exception.Message }
    }
  }

  if (-not $out) {
    $out = @([pscustomobject]@{ Computer=$env:COMPUTERNAME; TaskName="(none)"; RunAs=""; NextRunTime=$null; Status="NO TASKS CREATED"; Error="User list empty or task creation skipped." })
  }

  return $out
}

# ---------- EXECUTION ----------
$results = @()

foreach ($c in $Computers) {
  $users = @($Assignments | Where-Object { $_.Device -ieq $c } | ForEach-Object { $_.Sam })

  Write-Host "`n=== Deploying & Scheduling on ${c} ==="
  Write-Host "Users for ${c}: $($users -join ', ')"

  try {
    $r = Invoke-Command -ComputerName $c -Credential $RemoteAdminCred -ScriptBlock $deployBlock -ArgumentList `
      $runnerBytes, $RunnerLocalPath, $TaskNamePrefix, $DomainNetBIOS, $users, $DailyTime, $AlsoRunOnceIn5Min, $client4Short, $LabAdminPrincipal -ErrorAction Stop
    $results += $r
  } catch {
    $results += [pscustomobject]@{ Computer=$c; TaskName=$null; RunAs=$null; NextRunTime=$null; Status="FAIL (WinRM)"; Error=$_.Exception.Message }
  }
}

"`n=== SUMMARY ==="
$results | Sort-Object Computer, TaskName | Format-Table -AutoSize

"`nResults on each endpoint: C:\AtomicRedTeam\Results\"
"`nVerify tasks: Get-ScheduledTask | ? TaskName -like '$TaskNamePrefix*'"



