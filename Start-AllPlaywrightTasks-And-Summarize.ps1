<# 
Start-AllPlaywrightTasks-And-Summarize.ps1
Run from ADMIN machine.

What it does:
- Starts all PlaywrightCampaign-* tasks on CLIENT1-CLIENT3
- Starts ONLY PlaywrightCampaign-labadmin on CLIENT4
- Polls for completion (by ScheduledTaskInfo) and then prints a summary
- Prints latest playwright log + last_success sentinel (if present)

Adjust:
- $MaxWaitSeconds / $PollSeconds if your runs take longer.
#>

$ErrorActionPreference = "Stop"

$Computers = @("CLIENT1","CLIENT2","CLIENT3","CLIENT4")
$MaxWaitSeconds = 600   # 10 minutes
$PollSeconds    = 10

function Start-Tasks {
  param([string]$Computer)

  Invoke-Command -ComputerName $Computer -ScriptBlock {
    $tasks = Get-ScheduledTask | Where-Object { $_.TaskName -like "PlaywrightCampaign-*" }

    if ($env:COMPUTERNAME -ieq "CLIENT4") {
      $tasks = $tasks | Where-Object { $_.TaskName -eq "PlaywrightCampaign-labadmin" }
    }

    if (-not $tasks) {
      return [pscustomobject]@{ Computer=$env:COMPUTERNAME; Started=0; Note="No tasks found" }
    }

    $started = 0
    foreach ($t in $tasks) {
      try {
        Start-ScheduledTask -TaskName $t.TaskName
        $started++
      } catch {
        # continue
      }
    }

    [pscustomobject]@{ Computer=$env:COMPUTERNAME; Started=$started; Note="Started" }
  }
}

function Wait-And-Summarize {
  param([string]$Computer, [int]$MaxWaitSeconds, [int]$PollSeconds)

  Invoke-Command -ComputerName $Computer -ScriptBlock {
    param($MaxWaitSeconds, $PollSeconds)

    function Get-TasksToWatch {
      $t = Get-ScheduledTask | Where-Object { $_.TaskName -like "PlaywrightCampaign-*" }
      if ($env:COMPUTERNAME -ieq "CLIENT4") { $t = $t | Where-Object { $_.TaskName -eq "PlaywrightCampaign-labadmin" } }
      return $t
    }

    $tasks = Get-TasksToWatch
    if (-not $tasks) {
      return [pscustomobject]@{
        Computer=$env:COMPUTERNAME
        Watched=0
        Completed=0
        TimedOut=$false
        LastSuccess=$null
        LatestLog=$null
        Note="No tasks found"
      }
    }

    $deadline = (Get-Date).AddSeconds($MaxWaitSeconds)
    $done = $false

    while ((Get-Date) -lt $deadline -and -not $done) {
      $infos = foreach ($t in $tasks) {
        $i = Get-ScheduledTaskInfo -TaskName $t.TaskName
        [pscustomobject]@{
          TaskName=$t.TaskName
          LastRunTime=$i.LastRunTime
          LastTaskResult=$i.LastTaskResult
        }
      }

      # Consider a task "in progress" if it recently ran and is still "running" (0x41301)
      $inProgress = $infos | Where-Object { $_.LastTaskResult -eq 267009 } # 0x41301
      if (-not $inProgress) { $done = $true; break }

      Start-Sleep -Seconds $PollSeconds
      $tasks = Get-TasksToWatch
    }

    $tasksFinal = Get-TasksToWatch
    $finalInfos = foreach ($t in $tasksFinal) {
      $i = Get-ScheduledTaskInfo -TaskName $t.TaskName
      [pscustomobject]@{
        TaskName=$t.TaskName
        LastRunTime=$i.LastRunTime
        LastTaskResult=$i.LastTaskResult
      }
    }

    $successPath = "C:\AtomicRedTeam\Logs\playwright_last_success.txt"
    $lastSuccess = $null
    if (Test-Path $successPath) {
      $lastSuccess = (Get-Content $successPath -ErrorAction SilentlyContinue | Select-Object -First 1)
    }

    $latestLog = $null
    $log = Get-ChildItem "C:\AtomicRedTeam\Logs\playwright_$($env:COMPUTERNAME)_*.log" -ErrorAction SilentlyContinue |
           Sort-Object LastWriteTime -Desc | Select-Object -First 1
    if ($log) { $latestLog = $log.Name }

    [pscustomobject]@{
      Computer     = $env:COMPUTERNAME
      Watched      = $tasksFinal.Count
      Completed    = ($finalInfos | Where-Object { $_.LastTaskResult -eq 0 }).Count
      TimedOut     = (-not $done)
      LastSuccess  = $lastSuccess
      LatestLog    = $latestLog
      TaskResults  = ($finalInfos | ForEach-Object { "$($_.TaskName)=$($_.LastTaskResult)" }) -join "; "
      Note         = "Done"
    }
  } -ArgumentList $MaxWaitSeconds, $PollSeconds
}

Write-Host "Starting PlaywrightCampaign tasks across all clients..."
$startResults = foreach ($c in $Computers) {
  try { Start-Tasks -Computer $c } catch { [pscustomobject]@{ Computer=$c; Started=0; Note=$_.Exception.Message } }
}
$startResults | Format-Table -AutoSize
Write-Host ""

Write-Host "Waiting for completion (up to $MaxWaitSeconds seconds)..."
$sum = foreach ($c in $Computers) {
  try { Wait-And-Summarize -Computer $c -MaxWaitSeconds $MaxWaitSeconds -PollSeconds $PollSeconds }
  catch { [pscustomobject]@{ Computer=$c; Watched=0; Completed=0; TimedOut=$true; LastSuccess=$null; LatestLog=$null; TaskResults=$null; Note=$_.Exception.Message } }
}

$sum | Select-Object Computer, Watched, Completed, TimedOut, LatestLog, LastSuccess, TaskResults, Note | Format-List
