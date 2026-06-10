# --- 0. FORCE WINDOWS TERMINAL LAUNCH FOR EXE ---
if ($null -eq $env:WT_SESSION) {
    if (Get-Command "wt.exe" -ErrorAction SilentlyContinue) {
        # Get the literal path of the running .exe file
        $ExePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        
        # Relaunch the EXE inside Windows Terminal and exit the legacy console
        Start-Process "wt.exe" -ArgumentList "`"$ExePath`""
        Exit
    }
}
# --------------------------------------------------------

# 1. Administrator Check (Self-Elevating Fallback)
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $ExePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    # Automatically prompts for UAC admin rights rather than just crashing
    Start-Process "$ExePath" -Verb RunAs
    Exit
}

# Load GUI Assemblies
Add-Type -AssemblyName System.Windows.Forms

# 2. Executable Path Logic
$CurrentDir = Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
if ([string]::IsNullOrEmpty($CurrentDir)) { $CurrentDir = Get-Location }

# Logo
# Clear the host to give it a clean slate
Clear-Host

# Set the output encoding to UTF-8 to ensure characters render perfectly
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Colors mapping to your original design
$Teal = "DarkCyan"
$White = "White"

# The Custom Cleaning Icon Banner
Write-Host "               ,▄▄██████████▄▄,               " -ForegroundColor $Teal
Write-Host "            ▄████▀▀▀        ▀▀████▄           " -ForegroundColor $Teal
Write-Host "          ████▀                  ▀███▄        " -ForegroundColor $Teal
Write-Host "        ▄███▀          ▓▓          ▀███▄      " -ForegroundColor $Teal
Write-Host "       ███▀           ▓▓             ▀███     " -ForegroundColor $Teal
Write-Host "      ███            ▓▓               ███     " -ForegroundColor $Teal
Write-Host "     ███            ▓▓                 ███    " -ForegroundColor $Teal
Write-Host "     ███          ▄███▄         ░░     ███    " -ForegroundColor $Teal
Write-Host "     ███   •     ███████       ░░░     ███    " -ForegroundColor $Teal
Write-Host "     ███  •●    █████████     ══       ███    " -ForegroundColor $Teal
Write-Host "     ███ ▄▄█▄  ███████████   ═══       ███    " -ForegroundColor $Teal
Write-Host "      ███ ▀▀  █████████████           ███     " -ForegroundColor $Teal
Write-Host "       ███▄   ▀▀▀▀▀▀▀▀▀▀▀▀▀          ▄███     " -ForegroundColor $Teal
Write-Host "        ▀███▄ ════════════════════ ▄███▀      " -ForegroundColor $Teal
Write-Host "          ▀████▄                ▄████▀        " -ForegroundColor $Teal
Write-Host "            ▀██████████████████████▀          " -ForegroundColor $Teal
Write-Host "               ▀▀▀████████████▀▀▀             " -ForegroundColor $Teal

Write-Host ""
# Subtitles matching your screenshot style
Write-Host "===== Myles Mattlock CleanUp =====" -ForegroundColor $White

# --- CONFIGURATION ---
$CurrentVersion = "2.0.1" 
$RepoName = "Myles-Mattlock/CleanUp-Tool"
$RegFiles = @("DiskCleanupSettings.reg", "DiskCleanupSettings2.reg") 
$LogDir = "C:\Program Files\SystemCleanUp\Logs"
# ---------------------

# --- UPDATE CHECKER (STABLE ONLY) ---
function Check-ForUpdates {
    Write-Host "Checking for updates..." -ForegroundColor Gray
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) PowerShell-App"
        $Url = "https://api.github.com/repos/$RepoName/releases"

        # Fetch releases and filter out anything marked as a Prerelease (Beta)
        $Releases = Invoke-RestMethod -Uri $Url -Method Get -UserAgent $UserAgent -ErrorAction Stop
        $StableReleases = $Releases | Where-Object { $_.prerelease -eq $false }

        $LocalVersion = [version]($CurrentVersion.ToLower().TrimStart('v').Split("-")[0])
        $UpdateFound = $null

        foreach ($Rel in $StableReleases) {
            $RemoteVersion = [version]($Rel.tag_name.ToLower().TrimStart('v').Split("-")[0])

            if ($RemoteVersion -gt $LocalVersion) {
                $UpdateFound = $Rel
                break 
            }
        }

        if ($UpdateFound) {
            Write-Host "----------------------------------------------------------" -ForegroundColor Cyan
            Write-Host " [!] NEW STABLE UPDATE AVAILABLE: $($UpdateFound.tag_name)" -ForegroundColor White -BackgroundColor Blue
            Write-Host " You are currently running: v$CurrentVersion" -ForegroundColor Gray
            Write-Host " Download: $($UpdateFound.html_url)" -ForegroundColor Cyan
            Write-Host "----------------------------------------------------------" -ForegroundColor Cyan
            
            $UpdateChoice = [System.Windows.Forms.MessageBox]::Show("A new stable version ($($UpdateFound.tag_name)) is available.`n`nWould you like to download it now?", "Update Available", "YesNo", "Information", [System.Windows.Forms.MessageBoxDefaultButton]::Button1, [System.Windows.Forms.MessageBoxOptions]::ServiceNotification)
            
            if ($UpdateChoice -eq "Yes") { 
                Start-Process $UpdateFound.html_url
                Write-Host "Redirecting to download page. Closing app..." -ForegroundColor Yellow
                Start-Sleep -Seconds 2
                Exit 
            }
        } else {
            Write-Host " You are running the latest stable version (v$CurrentVersion)." -ForegroundColor DarkGreen
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

# 3. Import Registry Settings
Write-Host "`n[0/5] Importing Cleanup Configurations..." -ForegroundColor Yellow
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

# 4. Confirmation Pop-up
$PopTitle = "CleanUp Tool Confirmation"
$PopText  = "Would you like to begin the system cleanup process now?`n`nThis will clear temp files, empty the recycle bin, and run DISM optimization?"
$Result = [System.Windows.Forms.MessageBox]::Show($PopText, $PopTitle, "YesNo", "Question", [System.Windows.Forms.MessageBoxDefaultButton]::Button1, [System.Windows.Forms.MessageBoxOptions]::ServiceNotification)

if ($Result -eq "No") {
    Write-Host "`nOperation cancelled by user." -ForegroundColor Red
    Start-Sleep -Seconds 2
    Exit
}

# --- CLEANUP LOGIC ---
$CleanupTimer = [System.Diagnostics.Stopwatch]::StartNew()
try {
    Write-Host "`n[1/5] Clearing temporary files and logs..." -ForegroundColor Yellow
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

    Write-Host "[2/5] Emptying Recycle Bin..." -ForegroundColor Yellow
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue

    Write-Host "[3/5] Running Disk Cleanup Utility..." -ForegroundColor Yellow
    $CleanParam = if (Test-Path "C:\Windows.old") { "/SAGERUN:1" } else { "/SAGERUN:2" }
    Start-Process "cleanmgr.exe" -ArgumentList $CleanParam -Wait

    Write-Host "[4/5] Flushing DNS" -ForegroundColor Yellow
    ipconfig /flushdns

    Write-Host "[5/5] Optimizing Component Store (DISM)..." -ForegroundColor Yellow
    Dism.exe /online /Cleanup-Image /StartComponentCleanup /ResetBase /NoRestart

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