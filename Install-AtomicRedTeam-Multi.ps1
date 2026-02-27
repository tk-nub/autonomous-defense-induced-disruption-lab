<#
Installs Atomic Red Team + Invoke-Atomic on multiple remote Windows hosts.
- Uses PSRemoting (WinRM)
- Installs to C:\AtomicRedTeam by default
- Installs NuGet + PowerShellGet prereqs
- Installs Invoke-Atomic module
- Optionally pulls the AtomicRedTeam repo
#>

param(
    [Parameter(Mandatory)]
    [string[]]$Computers,

    [string]$InstallDir = "C:\AtomicRedTeam",

    # If you want to pull the repo (recommended), keep $true
    [bool]$CloneRepo = $true,

    # If your endpoints can reach GitHub directly, keep $true
    # If not, set $false and use your internal mirror or pre-stage the repo.
    [bool]$UseGitHub = $true
)

$scriptBlock = {
    param($InstallDir, $CloneRepo, $UseGitHub)

    function Write-Log {
        param([string]$Msg)
        Write-Host "[$env:COMPUTERNAME] $Msg"
    }

    try {
        Write-Log "Starting Atomic Red Team install..."

        # Ensure TLS 1.2 for downloads on older boxes
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

        # Create install directory
        if (-not (Test-Path $InstallDir)) {
            New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null
            Write-Log "Created $InstallDir"
        }

        # Make PSGallery trusted for non-interactive installs (optional; remove if you prefer prompts)
        try {
            Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted -ErrorAction Stop
            Write-Log "Set PSGallery to Trusted"
        } catch {
            Write-Log "PSGallery trust not changed (may already be set): $($_.Exception.Message)"
        }

        # Install NuGet provider
        try {
            if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction Stop | Out-Null
                Write-Log "Installed NuGet provider"
            } else {
                Write-Log "NuGet provider already present"
            }
        } catch {
            throw "Failed to install NuGet provider: $($_.Exception.Message)"
        }

        # Ensure PowerShellGet (sometimes needed on older hosts)
        try {
            $psget = Get-Module -ListAvailable -Name PowerShellGet | Sort-Object Version -Descending | Select-Object -First 1
            if (-not $psget) {
                Install-Module -Name PowerShellGet -Force -ErrorAction Stop
                Write-Log "Installed PowerShellGet"
            } else {
                Write-Log "PowerShellGet present (v$($psget.Version))"
            }
        } catch {
            Write-Log "PowerShellGet install/update skipped: $($_.Exception.Message)"
        }

        # Install Invoke-Atomic
        try {
            if (-not (Get-Module -ListAvailable -Name Invoke-AtomicRedTeam)) {
                Install-Module -Name Invoke-AtomicRedTeam -Force -ErrorAction Stop
                Write-Log "Installed Invoke-AtomicRedTeam module"
            } else {
                Write-Log "Invoke-AtomicRedTeam already installed"
            }
        } catch {
            throw "Failed to install Invoke-AtomicRedTeam: $($_.Exception.Message)"
        }

        # Clone Atomic Red Team tests repo (YAML) so you have the atomics locally
        if ($CloneRepo) {
            $repoDir = Join-Path $InstallDir "atomic-red-team"

            if (Test-Path $repoDir) {
                Write-Log "Repo already exists at $repoDir (skipping clone)"
            } else {
                if (-not $UseGitHub) {
                    throw "CloneRepo is true but UseGitHub is false. Provide your internal repo/mirror logic here."
                }

                # Option 1: Use git if present
                $git = Get-Command git -ErrorAction SilentlyContinue
                if ($git) {
                    Write-Log "Cloning repo via git..."
                    & git clone "https://github.com/redcanaryco/atomic-red-team.git" $repoDir 2>&1 | Out-Null
                    Write-Log "Cloned to $repoDir"
                } else {
                    # Option 2: Zip download (no git needed)
                    Write-Log "Git not found. Downloading repo zip..."
                    $zip = Join-Path $InstallDir "atomic-red-team.zip"
                    Invoke-WebRequest -Uri "https://github.com/redcanaryco/atomic-red-team/archive/refs/heads/master.zip" -OutFile $zip -UseBasicParsing -ErrorAction Stop
                    Expand-Archive -Path $zip -DestinationPath $InstallDir -Force
                    Remove-Item $zip -Force -ErrorAction SilentlyContinue

                    # GitHub zip expands to atomic-red-team-master; rename for consistency
                    $expanded = Join-Path $InstallDir "atomic-red-team-master"
                    if (Test-Path $expanded) {
                        Rename-Item -Path $expanded -NewName "atomic-red-team" -Force
                    }
                    Write-Log "Downloaded and expanded to $repoDir"
                }
            }
        }

        # Quick validation
        Write-Log "Validating module import..."
        Import-Module Invoke-AtomicRedTeam -ErrorAction Stop
        Write-Log "Invoke-AtomicRedTeam imported successfully."

        Write-Log "DONE."
        return $true
    }
    catch {
        Write-Log "ERROR: $($_.Exception.Message)"
        return $false
    }
}

# Get creds once (domain admin / local admin)
$cred = Get-Credential -Message "Enter admin creds for remote VMs"

$results = foreach ($c in $Computers) {
    try {
        Invoke-Command -ComputerName $c -Credential $cred -ScriptBlock $scriptBlock -ArgumentList $InstallDir, $CloneRepo, $UseGitHub -ErrorAction Stop |
            ForEach-Object {
                [pscustomobject]@{
                    Computer = $c
                    Success  = $_
                }
            }
    } catch {
        [pscustomobject]@{
            Computer = $c
            Success  = $false
            Error    = $_.Exception.Message
        }
    }
}

$results | Format-Table -AutoSize
