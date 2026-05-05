<#
.SYNOPSIS
    Optimized System Cleanup Script
.DESCRIPTION
    Clears temp files, empties recycle bin, runs Disk Cleanup, 
    and optimizes the DISM component store.
#>

# 1. Administrator Check
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "----------------------------------------------------------" -ForegroundColor Red
    Write-Host " ERROR: THIS SCRIPT REQUIRES ADMINISTRATIVE PRIVILEGES." -ForegroundColor Red
    Write-Host " Please right-click and 'Run as Administrator'." -ForegroundColor Red
    Write-Host "----------------------------------------------------------" -ForegroundColor Red
    Write-Host "Press any key to exit..."
    $null = [Console]::ReadKey($true)
    Exit
}

# 2. Setup Logging and Directories
$LogDir = "C:\Logs"
$LogFile = "$LogDir\SystemCleanUpErrors.log"
if (!(Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }

Write-Host "Running as Administrator. Preparing cleanup..." -ForegroundColor Cyan

# 3. User Confirmation (Native PowerShell prompt is faster than WinForms)
$Confirmation = Read-Host "This script will clear cache, recycle bin, and system logs. Proceed? (Y/N)"
if ($Confirmation -notmatch "y|yes") {
    Write-Host "Operation cancelled by user." -ForegroundColor Yellow
    Start-Sleep -Seconds 2
    Exit
}

try {
    # 4. Manual Folder Cleanup (Temp, Prefetch, SoftwareDistribution)
    Write-Host "`n[1/4] Cleaning temporary directories..." -ForegroundColor Yellow
    $TargetFolders = @(
        "C:\Windows\Temp\*",
        "C:\Windows\Prefetch\*",
        "C:\Windows\SoftwareDistribution\Download\*",
        "$([System.IO.Path]::GetTempPath())*"
    )

    foreach ($Path in $TargetFolders) {
        Write-Host "  > Clearing: $Path" -ForegroundColor Gray
        Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 5. Empty Recycle Bin
    Write-Host "[2/4] Emptying all Recycle Bins..." -ForegroundColor Yellow
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue

    # 6. Windows Disk Cleanup (cleanmgr.exe)
    # Using -Wait ensures the script moves on as soon as the process finishes, 
    # rather than waiting for a hardcoded number of seconds.
    if (Test-Path "C:\Windows.old") {
        Write-Host "[3/4] Windows.old detected. Running Deep Cleanup..." -ForegroundColor Yellow
        Start-Process "cleanmgr.exe" -ArgumentList "/SAGERUN:1" -Wait
    } else {
        Write-Host "[3/4] Running standard Disk Cleanup..." -ForegroundColor Yellow
        Start-Process "cleanmgr.exe" -ArgumentList "/SAGERUN:2" -Wait
    }

    # 7. Component Store Cleanup (DISM)
    # This recovers space from old Windows Updates
    Write-Host "[4/4] Optimizing Component Store (DISM)..." -ForegroundColor Yellow
    Dism.exe /online /Cleanup-Image /StartComponentCleanup /ResetBase /NoRestart

    Write-Host "`n----------------------------------------------------------" -ForegroundColor Green
    Write-Host " SUCCESS: Windows System Cleanup Completed!" -ForegroundColor Green
    Write-Host "----------------------------------------------------------" -ForegroundColor Green

} catch {
    $ErrorMessage = "$(Get-Date -Format 'dd-MM-yyyy HH:mm:ss'): $($_.Exception.Message)"
    Add-Content -Path $LogFile -Value $ErrorMessage
    Write-Host "`nAn error occurred during cleanup. Details logged to $LogFile" -ForegroundColor Red
}

Write-Host "Closing in 5 seconds..."
Start-Sleep -Seconds 5