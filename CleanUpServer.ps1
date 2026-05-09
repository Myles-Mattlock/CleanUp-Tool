# --- 0. FORCE WINDOWS TERMINAL LAUNCH ---
# Check if we are NOT in Windows Terminal (WT_SESSION is only set in WT)
if ($null -eq $env:WT_SESSION) {
    # Check if Windows Terminal is installed on the system
    if (Get-Command "wt.exe" -ErrorAction SilentlyContinue) {
        $currentProcess = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        
        # If running as .exe, launch the .exe. Otherwise, launch the .ps1
        if ($currentProcess -like "*powershell.exe*") {
            Start-Process "wt.exe" -ArgumentList "powershell.exe -NoExit -File `"$PSCommandPath`""
        } else {
            Start-Process "wt.exe" -ArgumentList "`"$currentProcess`""
        }
        exit
    }
}
# -----------------------------------------

# 1. Administrator Check
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "----------------------------------------------------------" -ForegroundColor Red
    Write-Host " ERROR: THIS TOOL REQUIRES ADMINISTRATIVE PRIVILEGES." -ForegroundColor Red
    Write-Host "----------------------------------------------------------" -ForegroundColor Red
    Write-Host "Please restart the application as Administrator."
    Write-Host "Press any key to exit..."
    $null = [Console]::ReadKey($true)
    Exit
}

# Load GUI Assemblies
Add-Type -AssemblyName System.Windows.Forms

# 2. Robust Path Logic
if ([System.IO.Path]::GetExtension($PSCommandPath) -eq '.exe') {
    $CurrentDir = Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
} else {
    $CurrentDir = $PSScriptRoot
}
if ([string]::IsNullOrEmpty($CurrentDir)) { $CurrentDir = Get-Location }

# --- CONFIGURATION ---
$CurrentVersion = "2.0.0-beta.41" 
$RepoName = "Myles-Mattlock/CleanUp-Tool"
$RegFiles = @("DiskCleanupSettings.reg", "DiskCleanupSettings2.reg") 
$LogDir = "C:\Logs"
# ---------------------

# --- UPDATE CHECKER ---
function Check-ForUpdates {
    Write-Host "Checking for updates..." -ForegroundColor Gray
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) PowerShell-App"
        $Url = "https://api.github.com/repos/$RepoName/releases"

        $Releases = Invoke-RestMethod -Uri $Url -Method Get -UserAgent $UserAgent -ErrorAction Stop
        $LocalTag = $CurrentVersion.ToLower().TrimStart('v')
        $LocalVersionBase = [version]($LocalTag.Split("-")[0])
        $UpdateFound = $null

        foreach ($Rel in $Releases) {
            $RemoteTag = $Rel.tag_name.ToLower().TrimStart('v')
            $RemoteVersionBase = [version]($RemoteTag.Split("-")[0])

            if ($RemoteVersionBase -gt $LocalVersionBase) {
                $UpdateFound = $Rel
                break 
            }
            if ($RemoteVersionBase -eq $LocalVersionBase -and $RemoteTag -ne $LocalTag) {
                if ($RemoteTag.Length -lt $LocalTag.Length -or $RemoteTag -gt $LocalTag) {
                    $UpdateFound = $Rel
                    break
                }
            }
        }

        if ($UpdateFound) {
            Write-Host "----------------------------------------------------------" -ForegroundColor Cyan
            $Label = if ($UpdateFound.prerelease) { "BETA UPDATE" } else { "STABLE UPDATE" }
            Write-Host " [!] NEW $Label AVAILABLE: $($UpdateFound.tag_name)" -ForegroundColor White -BackgroundColor Blue
            Write-Host " You are currently running: v$CurrentVersion" -ForegroundColor Gray
            Write-Host " Download: $($UpdateFound.html_url)" -ForegroundColor Cyan
            Write-Host "----------------------------------------------------------" -ForegroundColor Cyan
            
            $UpdateChoice = [System.Windows.Forms.MessageBox]::Show("A new version ($($UpdateFound.tag_name)) is available.`n`nWould you like to download it and close this version?", "Update Available", "YesNo", "Information", [System.Windows.Forms.MessageBoxDefaultButton]::Button1, [System.Windows.Forms.MessageBoxOptions]::ServiceNotification)
            
            if ($UpdateChoice -eq "Yes") { 
                Start-Process $UpdateFound.html_url
                Write-Host "Redirecting to download page. Closing app..." -ForegroundColor Yellow
                Start-Sleep -Seconds 2
                Exit 
            } else {
                Write-Host " Continuing with current version..." -ForegroundColor Gray
            }
        } else {
            Write-Host " You are running the latest version. Currently running: v$CurrentVersion" -ForegroundColor DarkGreen
        }
    } catch {
        Write-Host " Note: Update check skipped (Connection issue)." -ForegroundColor DarkGray
    }
}

# Capture Starting Disk Space
$Drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$StartingFreeSpace = $Drive.FreeSpace

# Ensure Log directory exists
if (!(Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }

Write-Host "`n--- Windows System Cleanup Tool ---" -ForegroundColor Cyan
Write-Host "Initial Free Space: $([Math]::Round($StartingFreeSpace / 1GB, 2)) GB" -ForegroundColor Gray

# Run the update check
Check-ForUpdates

# 3. Import Sageset Registry Settings
Write-Host "`n[0/3] Importing Cleanup Configurations..." -ForegroundColor Yellow
foreach ($File in $RegFiles) {
    $FilePath = Join-Path $CurrentDir $File
    if (Test-Path $FilePath) {
        $proc = Start-Process "reg.exe" -ArgumentList "import `"$FilePath`"" -Wait -PassThru -WindowStyle Hidden
        if ($proc.ExitCode -eq 0) {
            Write-Host "  > Successfully applied: $File" -ForegroundColor Gray
        } else {
            Write-Warning "  > Failed to apply $File (Code: $($proc.ExitCode))"
        }
    } else {
        Write-Warning "  > Registry file not found: $FilePath"
    }
}

# 4. User Confirmation Pop-up
$PopTitle = "CleanUp Tool Confirmation"
$PopText  = "Would you like to begin the system cleanup process now?`n`nThis will clear temp files, empty the recycle bin?"
$PopButtons = [System.Windows.Forms.MessageBoxButtons]::YesNo
$PopIcon = [System.Windows.Forms.MessageBoxIcon]::Question

$Result = [System.Windows.Forms.MessageBox]::Show($PopText, $PopTitle, $PopButtons, $PopIcon, [System.Windows.Forms.MessageBoxDefaultButton]::Button1, [System.Windows.Forms.MessageBoxOptions]::ServiceNotification)

if ($Result -eq "No") {
    Write-Host "`nOperation cancelled by user." -ForegroundColor Red
    Start-Sleep -Seconds 2
    Exit
}

# --- CLEANUP LOGIC ---
$CleanupTimer = [System.Diagnostics.Stopwatch]::StartNew()
try {
    Write-Host "`n[1/3] Clearing temporary files and logs..." -ForegroundColor Yellow
    $TargetFolders = @(
        "C:\Windows\Temp\*",
        "C:\Windows\Prefetch\*",
        "C:\Windows\SoftwareDistribution\Download\*",
        "$([System.IO.Path]::GetTempPath())*",
        "C:\Intel",
        "C:\PerfLogs"
    )
    
    foreach ($Path in $TargetFolders) {
        if (Test-Path $Path) {
            Write-Host "  > Cleaning: $Path" -ForegroundColor Gray
            Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Host "[2/3] Emptying Recycle Bin..." -ForegroundColor Yellow
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue

    Write-Host "[3/3] Running Disk Cleanup Utility..." -ForegroundColor Yellow
    $CleanParam = if (Test-Path "C:\Windows.old") { "/SAGERUN:1" } else { "/SAGERUN:2" }
    Start-Process "cleanmgr.exe" -ArgumentList $CleanParam -Wait

    $CleanupTimer.Stop()
    $DriveEnd = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $SpaceSavedBytes = $DriveEnd.FreeSpace - $StartingFreeSpace
    
    $ReadableSpace = if ($SpaceSavedBytes -le 0) {
        "0 MB"
    } elseif ($SpaceSavedBytes -gt 1GB) {
        "$([Math]::Round($SpaceSavedBytes / 1GB, 2)) GB"
    } else {
        "$([Math]::Round($SpaceSavedBytes / 1MB, 2)) MB"
    }

    Write-Host "`n----------------------------------------------------------" -ForegroundColor Green
    Write-Host " SUCCESS: Cleanup process finished!" -ForegroundColor Green
    Write-Host " TOTAL STORAGE RECLAIMED: $ReadableSpace" -ForegroundColor White -BackgroundColor DarkGreen
    Write-Host " TIME ELAPSED: $("{0:mm} min {0:ss} sec" -f $CleanupTimer.Elapsed)" -ForegroundColor White
    Write-Host "----------------------------------------------------------" -ForegroundColor Green

} catch {
    $ErrorMessage = "$(Get-Date -Format 'dd-MM-yyyy HH:mm:ss'): $($_.Exception.Message)"
    Add-Content -Path "$LogDir\SystemCleanUpErrors.log" -Value $ErrorMessage
    Write-Host "`nAn error occurred. See $LogDir\SystemCleanUpErrors.log" -ForegroundColor Red
}

Write-Host "Press any key to exit..."
$null = [Console]::ReadKey($true)
Exit