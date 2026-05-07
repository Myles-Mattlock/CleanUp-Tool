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
$CurrentVersion = "2.0.1" 
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
            if ($RemoteVersionBase -gt $LocalVersionBase) { $UpdateFound = $Rel; break }
        }
        if ($UpdateFound) {
            Write-Host " [!] NEW UPDATE AVAILABLE: $($UpdateFound.tag_name)" -ForegroundColor White -BackgroundColor Blue
        }
    } catch {
        Write-Host " Note: Update check skipped." -ForegroundColor DarkGray
    }
}

# Capture Starting Disk Space
$Drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$StartingFreeSpace = $Drive.FreeSpace
if (!(Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }

Write-Host "`n--- Windows System Cleanup Tool ---" -ForegroundColor Cyan
Write-Host "Initial Free Space: $([Math]::Round($StartingFreeSpace / 1GB, 2)) GB" -ForegroundColor Gray

Check-ForUpdates

# 3. Import Sageset Registry Settings
Write-Host "`n[0/3] Importing Cleanup Configurations..." -ForegroundColor Yellow
foreach ($File in $RegFiles) {
    $FilePath = Join-Path $CurrentDir $File
    if (Test-Path $FilePath) {
        Start-Process "reg.exe" -ArgumentList "import `"$FilePath`"" -Wait -WindowStyle Hidden
    }
}

# 4. User Confirmation
Write-Host ""
$Confirmation = Read-Host "Begin system cleanup? (Y/N)"
if ($Confirmation -notmatch "y|yes") { Exit }

# --- CLEANUP LOGIC ---
$CleanupTimer = [System.Diagnostics.Stopwatch]::StartNew()
try {
    Write-Host "`n[1/3] Clearing temporary files and system folders..." -ForegroundColor Yellow
    
    # 1. Folders where we only want to empty the CONTENTS
    $ContentOnly = @(
        "C:\Windows\Temp\*",
        "C:\Windows\Prefetch\*",
        "C:\Windows\SoftwareDistribution\Download\*",
        "$([System.IO.Path]::GetTempPath())*"
    )

    # 2. Folders we want to DELETE ENTIRELY
    $FullDelete = @(
        "C:\Intel",
        "C:\PerfLogs"
    )

    # Process Content Only
    foreach ($Path in $ContentOnly) {
        if (Test-Path $Path) {
            Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # Process Full Folder Deletion (with permission takeover)
    foreach ($Folder in $FullDelete) {
        if (Test-Path $Folder) {
            Write-Host "  > Force removing: $Folder" -ForegroundColor Gray
            # Take ownership and grant full control to bypass "Access Denied"
            takeown /f "$Folder" /r /d y > $null
            icacls "$Folder" /grant administrators:F /t /q > $null
            # Remove the folder
            Remove-Item $Folder -Recurse -Force -ErrorAction SilentlyContinue
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
    $ReadableSpace = if ($SpaceSavedBytes -le 0) { "0 MB" } elseif ($SpaceSavedBytes -gt 1GB) { "$([Math]::Round($SpaceSavedBytes / 1GB, 2)) GB" } else { "$([Math]::Round($SpaceSavedBytes / 1MB, 2)) MB" }

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