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
$RegFiles = @("DiskCleanupSettings.reg", "DiskCleanupSettings2.reg") 
$LogDir = "C:\Logs"
# ---------------------

# Capture Starting Disk Space
$Drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$StartingFreeSpace = $Drive.FreeSpace

# Ensure Log directory exists
if (!(Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }

Write-Host "--- Windows System Cleanup Tool ---" -ForegroundColor Cyan
Write-Host "Running from: $CurrentDir" -ForegroundColor Gray
Write-Host "Initial Free Space: $([Math]::Round($StartingFreeSpace / 1GB, 2)) GB" -ForegroundColor Gray

# 3. Import Sageset Registry Settings
Write-Host "`n[1/5] Importing Cleanup Configurations..." -ForegroundColor Yellow
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

# 4. User Confirmation
Write-Host ""
$Confirmation = Read-Host "Begin system cleanup? (Y/N)"
if ($Confirmation -notmatch "y|yes") {
    Write-Host "Operation cancelled." -ForegroundColor Red
    Start-Sleep -Seconds 2
    Exit
}

try {
    # 5. Manual Folder Cleanup
    Write-Host "`n[2/5] Clearing temporary files..." -ForegroundColor Yellow
    $TargetFolders = @(
        "C:\Windows\Temp\*",
        "C:\Windows\Prefetch\*",
        "C:\Windows\SoftwareDistribution\Download\*",
        "$([System.IO.Path]::GetTempPath())*"
    )

    foreach ($Path in $TargetFolders) {
        Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 6. Empty Recycle Bin
    Write-Host "[3/5] Emptying Recycle Bin..." -ForegroundColor Yellow
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue

    # 7. Disk Cleanup (cleanmgr.exe)
    Write-Host "[4/5] Running Disk Cleanup Utility..." -ForegroundColor Yellow
    $CleanParam = if (Test-Path "C:\Windows.old") { "/SAGERUN:1" } else { "/SAGERUN:2" }
    Start-Process "cleanmgr.exe" -ArgumentList $CleanParam -Wait

    # 8. Component Store Cleanup (DISM)
    Write-Host "[5/5] Optimizing Component Store (DISM)..." -ForegroundColor Yellow
    Dism.exe /online /Cleanup-Image /StartComponentCleanup /ResetBase /NoRestart

    # --- FINAL CALCULATION ---
    $DriveEnd = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $EndingFreeSpace = $DriveEnd.FreeSpace
    $SpaceSavedBytes = $EndingFreeSpace - $StartingFreeSpace

    # Format output (MB or GB)
    if ($SpaceSavedBytes -gt 1GB) {
        $ReadableSpace = "$([Math]::Round($SpaceSavedBytes / 1GB, 2)) GB"
    } else {
        $ReadableSpace = "$([Math]::Round($SpaceSavedBytes / 1MB, 2)) MB"
    }

    Write-Host "`n----------------------------------------------------------" -ForegroundColor Green
    Write-Host " SUCCESS: Cleanup process finished!" -ForegroundColor Green
    Write-Host " TOTAL STORAGE RECLAIMED: $ReadableSpace" -ForegroundColor White -BackgroundColor DarkGreen
    Write-Host "----------------------------------------------------------" -ForegroundColor Green

} catch {
    $ErrorMessage = "$(Get-Date -Format 'dd-MM-yyyy HH:mm:ss'): $($_.Exception.Message)"
    Add-Content -Path "$LogDir\SystemCleanUpErrors.log" -Value $ErrorMessage
    Write-Host "`nAn error occurred. See $LogDir\SystemCleanUpErrors.log" -ForegroundColor Red
}

Write-Host "Closing in 10 seconds..."
Start-Sleep -Seconds 10