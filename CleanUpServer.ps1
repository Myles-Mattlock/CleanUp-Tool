# 1. Administrator Check
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "----------------------------------------------------------" -ForegroundColor Red
    Write-Host " ERROR: THIS TOOL REQUIRES ADMINISTRATIVE PRIVILEGES." -ForegroundColor Red
    Write-Host "----------------------------------------------------------" -ForegroundColor Red
    Write-Host "Press any key to exit..."
    $null = [Console]::ReadKey($true)
    Exit
}

# 2. Robust Path Logic
if ([System.IO.Path]::GetExtension($PSCommandPath) -eq '.exe') {
    $CurrentDir = Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
} else {
    $CurrentDir = $PSScriptRoot
}
if ([string]::IsNullOrEmpty($CurrentDir)) { $CurrentDir = Get-Location }

# --- CONFIGURATION ---
$CurrentVersion = "2.0.1-Debug" 
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
        Write-Host " Update check completed." -ForegroundColor DarkGray
    } catch {
        Write-Host " Note: Update check skipped (Connection issue)." -ForegroundColor DarkGray
    }
}

# Capture Starting Disk Space
$Drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$StartingFreeSpace = $Drive.FreeSpace
if (!(Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }

Write-Host "`n--- Windows System Cleanup Tool (DEBUG MODE) ---" -ForegroundColor Cyan
Check-ForUpdates

# 3. Import Sageset Registry Settings
Write-Host "`n[0/3] Importing Cleanup Configurations..." -ForegroundColor Yellow
foreach ($File in $RegFiles) {
    $FilePath = Join-Path $CurrentDir $File
    if (Test-Path $FilePath) {
        $proc = Start-Process "reg.exe" -ArgumentList "import `"$FilePath`"" -Wait -PassThru -WindowStyle Hidden
        Write-Host "  > Applied: $File (Exit Code: $($proc.ExitCode))" -ForegroundColor Gray
    }
}

# 4. User Confirmation
Write-Host ""
$Confirmation = Read-Host "Begin system cleanup? (Y/N)"
if ($Confirmation -notmatch "y|yes") { Exit }

# --- CLEANUP LOGIC WITH DEBUGGING ---
$CleanupTimer = [System.Diagnostics.Stopwatch]::StartNew()
try {
    Write-Host "`n[1/3] Clearing files and folders..." -ForegroundColor Yellow
    
    $TargetFolders = @(
        "C:\Windows\Temp\*",
        "C:\Windows\Prefetch\*",
        "C:\Intel",
        "C:\PerfLogs",
        "C:\Windows\SoftwareDistribution\Download\*",
        "$([System.IO.Path]::GetTempPath())*"
    )

    foreach ($Path in $TargetFolders) {
        Write-Host "  [DEBUG] Processing: $Path" -ForegroundColor DarkCyan
        
        if (Test-Path $Path) {
            try {
                # Attempt removal
                Remove-Item $Path -Recurse -Force -ErrorAction Stop
                Write-Host "    [+] SUCCESS: Deleted $Path" -ForegroundColor Green
            } catch {
                # Identify WHY it failed
                Write-Host "    [-] FAILED: Could not delete $Path" -ForegroundColor Red
                Write-Host "    REASON: $($_.Exception.Message)" -ForegroundColor White -BackgroundColor DarkRed
                
                # Check if folder is locked by a process
                if ($_.Exception.Message -match "being used by another process") {
                    Write-Host "    TIP: A system service is currently using this folder." -ForegroundColor Yellow
                }
            }
        } else {
            Write-Host "    [!] SKIPPED: Path does not exist." -ForegroundColor DarkGray
        }
    }

    Write-Host "`n[2/3] Emptying Recycle Bin..." -ForegroundColor Yellow
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue

    Write-Host "[3/3] Running Disk Cleanup Utility..." -ForegroundColor Yellow
    $CleanParam = if (Test-Path "C:\Windows.old") { "/SAGERUN:1" } else { "/SAGERUN:2" }
    Start-Process "cleanmgr.exe" -ArgumentList $CleanParam -Wait

    $CleanupTimer.Stop()
    
    $DriveEnd = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $SpaceSavedBytes = $DriveEnd.FreeSpace - $StartingFreeSpace
    $ReadableSpace = if ($SpaceSavedBytes -le 0) { "0 MB" } else { "$([Math]::Round($SpaceSavedBytes / 1MB, 2)) MB" }

    Write-Host "`n----------------------------------------------------------" -ForegroundColor Green
    Write-Host " SUCCESS: Cleanup process finished!" -ForegroundColor Green
    Write-Host " TOTAL STORAGE RECLAIMED: $ReadableSpace" -ForegroundColor White -BackgroundColor DarkGreen
    Write-Host "----------------------------------------------------------" -ForegroundColor Green

} catch {
    Write-Host "`nCRITICAL ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "Press any key to exit..."
$null = [Console]::ReadKey($true)
Exit