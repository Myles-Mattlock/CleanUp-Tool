# 1. Administrator Check
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "THIS TOOL REQUIRES ADMINISTRATIVE PRIVILEGES. PLEASE RUN AS ADMINISTRATOR."
    Exit
}

# Load GUI Assemblies
Add-Type -AssemblyName System.Windows.Forms

# 2. Path Logic
if ([System.IO.Path]::GetExtension($PSCommandPath) -eq '.exe') {
    $CurrentDir = Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
} else {
    $CurrentDir = $PSScriptRoot
}
if ([string]::IsNullOrEmpty($CurrentDir)) { $CurrentDir = Get-Location }

# --- CONFIGURATION ---
$RegFiles = @("DiskCleanupSettings.reg", "DiskCleanupSettings2.reg") 
# ---------------------

# Capture Starting Disk Space
$Drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$StartingFreeSpace = $Drive.FreeSpace

Write-Host "`n--- Windows System Cleanup Tool (Automated) ---" -ForegroundColor Cyan
Write-Host "Initial Free Space: $([Math]::Round($StartingFreeSpace / 1GB, 2)) GB" -ForegroundColor Gray

# 3. Import Registry Settings
Write-Host "`n[1/4] Importing Cleanup Configurations..." -ForegroundColor Yellow
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

# --- CLEANUP LOGIC ---
$CleanupTimer = [System.Diagnostics.Stopwatch]::StartNew()

Write-Host "`n[2/4] Clearing temporary files and logs..." -ForegroundColor Yellow
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

Write-Host "[3/4] Emptying Recycle Bin..." -ForegroundColor Yellow
Clear-RecycleBin -Force -ErrorAction SilentlyContinue

Write-Host "[4/4] Optimizing Component Store (DISM)..." -ForegroundColor Yellow
Dism.exe /online /Cleanup-Image /StartComponentCleanup /ResetBase /NoRestart

# Run Disk Cleanup in the background
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

Exit