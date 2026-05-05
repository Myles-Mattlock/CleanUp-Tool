# 1. Administrator Check
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: Please run as Administrator." -ForegroundColor Red
    Pause ; Exit
}

# --- CONFIGURATION ---
# List your .reg filenames here (ensure they are in the same folder as this script)
$RegFiles = @("DiskCleanupSettings.reg", "DiskCleanupSettings2.reg") 
$LogDir = "C:\Logs"
# ---------------------

if (!(Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }

Write-Host "--- Starting Optimized System Cleanup ---" -ForegroundColor Cyan

# 2. Import Sageset Registry Settings
Write-Host "[0/5] Importing Registry Settings..." -ForegroundColor Yellow
foreach ($File in $RegFiles) {
    $FilePath = Join-Path $PSScriptRoot $File
    if (Test-Path $FilePath) {
        # Import silently
        $proc = Start-Process "reg.exe" -ArgumentList "import `"$FilePath`"" -Wait -PassThru -WindowStyle Hidden
        if ($proc.ExitCode -eq 0) {
            Write-Host "  > Successfully imported $File" -ForegroundColor Gray
        } else {
            Write-Warning "  > Failed to import $File (Exit Code: $($proc.ExitCode))"
        }
    } else {
        Write-Warning "  > Reg file not found: $File (Skipping)"
    }
}

# 3. User Confirmation
$Confirmation = Read-Host "`nReady to proceed with cleanup? (Y/N)"
if ($Confirmation -notmatch "y|yes") { Exit }

try {
    # 4. Manual Folder Cleanup
    Write-Host "`n[1/5] Clearing temp folders..." -ForegroundColor Yellow
    $TargetFolders = @(
        "C:\Windows\Temp\*",
        "C:\Windows\Prefetch\*",
        "C:\Windows\SoftwareDistribution\Download\*",
        "$([System.IO.Path]::GetTempPath())*"
    )
    foreach ($Path in $TargetFolders) {
        Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 5. Recycle Bin
    Write-Host "[2/5] Emptying Recycle Bin..." -ForegroundColor Yellow
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue

    # 6. Disk Cleanup (Using the imported Sageset settings)
    Write-Host "[3/5] Running Disk Cleanup..." -ForegroundColor Yellow
    $CleanParam = if (Test-Path "C:\Windows.old") { "/SAGERUN:1" } else { "/SAGERUN:2" }
    Start-Process "cleanmgr.exe" -ArgumentList $CleanParam -Wait

    # 7. DISM Optimization
    Write-Host "[4/5] Optimizing Component Store (DISM)..." -ForegroundColor Yellow
    Dism.exe /online /Cleanup-Image /StartComponentCleanup /ResetBase /NoRestart

    Write-Host "`nSUCCESS: System Cleanup Completed!" -ForegroundColor Green

} catch {
    $ErrorMessage = "$(Get-Date -Format 'dd-MM-yyyy HH:mm:ss'): $($_.Exception.Message)"
    Add-Content -Path "$LogDir\SystemCleanUpErrors.log" -Value $ErrorMessage
    Write-Error "Check $LogDir\SystemCleanUpErrors.log for details."
}

Write-Host "Closing in 5 seconds..."
Start-Sleep -Seconds 5