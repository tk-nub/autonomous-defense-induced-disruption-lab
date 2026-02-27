param(
  [string]$ResultsRoot = "C:\AtomicRedTeam\Results",
  [string]$AtomicRepo  = "C:\AtomicRedTeam\atomic-red-team",
  [string[]]$Techniques = @(,"T1047","T1105","T1566.001","T1566.002","T1486","T1059.001")
)

function Write-Log { param([string]$m) Write-Host "[$env:COMPUTERNAME] $m" }

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$outDir = Join-Path $ResultsRoot $ts
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
Start-Transcript -Path (Join-Path $outDir "transcript.txt") -Force | Out-Null

try {
  # Campaign markers for later correlation
  $CampaignId = "AtomicCampaign_" + (Get-Date -Format "yyyyMMdd_HHmmss")
  $UserUpn = (whoami /upn 2>$null)
  if (-not $UserUpn) { $UserUpn = "$env:USERDOMAIN\$env:USERNAME" }

  "$CampaignId	$UserUpn	$env:COMPUTERNAME	$(Get-Date -Format o)" |
    Out-File "C:\AtomicRedTeam\Results\campaign_marker.txt" -Append -Encoding utf8

  Write-Log "CampaignId: $CampaignId"
  Write-Log "User: $UserUpn"
  Write-Log "Output: $outDir"

  Import-Module Invoke-AtomicRedTeam -Force -ErrorAction Stop

  $atomicRoot  = $AtomicRepo
  $atomicsPath = Join-Path $atomicRoot "atomics"

  if (-not (Test-Path $atomicRoot))  { throw "Atomic repo not found at $atomicRoot" }
  if (-not (Test-Path $atomicsPath)) { throw "Atomics folder not found at $atomicsPath" }

  # Scheduled-task safe: set both vars (and we will also pass -Path explicitly)
  $env:ATOMIC_RED_TEAM_PATH = $atomicRoot
  $env:ATOMIC_RED_TEAM_DIR  = $atomicRoot
  $env:ATOMIC_RED_TEAM_DIR = $AtomicRepo
  if (-not (Test-Path $AtomicRepo)) { throw "Atomic repo not found at $AtomicRepo" }

  # Defender (best effort)
  try { Get-MpComputerStatus | ConvertTo-Json -Depth 5 | Out-File (Join-Path $outDir "defender_status.json") -Encoding utf8 } catch {}
  try {
    Get-MpThreatDetection | Select-Object * | Export-Csv (Join-Path $outDir "defender_threat_detections.csv") -NoTypeInformation -Force
    Get-MpThreat | Select-Object * | Export-Csv (Join-Path $outDir "defender_threats.csv") -NoTypeInformation -Force
  } catch {}

  # EVTX exports (best effort)
  $logs = @(
    @{Name="Microsoft-Windows-Windows Defender/Operational"; File="defender_operational.evtx"},
    @{Name="Microsoft-Windows-PowerShell/Operational";       File="powershell_operational.evtx"},
    @{Name="Security";                                      File="security.evtx"}
  )
  if (Get-WinEvent -ListLog "Microsoft-Windows-Sysmon/Operational" -ErrorAction SilentlyContinue) {
    $logs += @{Name="Microsoft-Windows-Sysmon/Operational"; File="sysmon_operational.evtx"}
  }
  foreach ($l in $logs) { try { wevtutil epl $l.Name (Join-Path $outDir $l.File) /ow:true } catch {} }
  foreach ($t in $Techniques) {
    if ([string]::IsNullOrWhiteSpace($t)) {
      Write-Log "Skipping empty technique entry"
      continue
    }
    Write-Log "Running $t"
    Invoke-AtomicTest $t -Path $atomicsPath -ErrorAction Continue *>&1 |
      Out-File (Join-Path $outDir "atomic_$t_run.txt") -Append -Encoding utf8
  }

  $zipPath = Join-Path $ResultsRoot ("AtomicResults_{0}_{1}.zip" -f $env:COMPUTERNAME, $ts)
  if (Test-Path $zipPath) { Remove-Item $zipPath -Force -ErrorAction SilentlyContinue }
  Compress-Archive -Path (Join-Path $outDir "*") -DestinationPath $zipPath -Force
  Write-Log "ZIP: $zipPath"
}
catch {
  Write-Log "ERROR: $($_.Exception.Message)"
  $_ | Out-String | Out-File (Join-Path $outDir "error.txt") -Force -Encoding utf8
}
finally {
  Stop-Transcript | Out-Null
}