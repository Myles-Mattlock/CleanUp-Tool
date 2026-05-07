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
$CurrentVersion = "v2.0.0-Beta.2"  # Format: v1.0.0 or v1.1.0-beta
$RepoName = "Myles-Mattlock/CleanUp-Tool"
$RegFiles = @("DiskCleanupSettings.reg", "DiskCleanupSettings2.reg") 
$LogDir = "C:\Logs"
# ---------------------

# --- UPDATE CHECKER ---
function Check-ForUpdates {
    Write-Host "Checking for updates..." -ForegroundColor Gray
    try {
        # Fetch all releases to include pre-releases/betas
        $AllReleasesUrl = "https://api.github.com/repos/$RepoName/releases"
        $Releases = Invoke-RestMethod -Uri $AllReleasesUrl -ErrorAction Stop
        
        # Convert local version string to a comparable object (removes 'v' prefix)
        $CurrentVerObj = [System.Management.Automation.SemanticVersion]($CurrentVersion.TrimStart('v'))
        
        # Sort GitHub releases by version and find the single newest one
        $LatestRelease = $Releases | ForEach-Object {
            try {
                [PSCustomObject]@{
                    Version = [System.Management.Automation.SemanticVersion]($_.tag_name.TrimStart('v'))
                    Url     = $_.html_url
                    Tag     = $_.tag_name
                    IsBeta  = $_.prerelease
                }
            } catch { $null } # Skip tags that aren't valid version numbers
        } | Sort-Object Version -Descending | Select-Object -First 1

        # Intelligent Comparison
        if ($LatestRelease -and ($LatestRelease.Version -gt $CurrentVerObj)) {
            Write-Host "----------------------------------------------------------" -ForegroundColor Cyan
            $StatusType = if ($LatestRelease.IsBeta) { "BETA UPDATE" } else { "UPDATE" }
            Write-Host " [!] NEW $StatusType AVAILABLE: $($LatestRelease.Tag)" -ForegroundColor White -BackgroundColor Blue
            Write-Host " You are currently running: $CurrentVersion" -ForegroundColor Gray
            Write-Host " Download here: $($LatestRelease.Url)" -ForegroundColor Cyan
            Write-Host "----------------------------------------------------------" -ForegroundColor Cyan
        } else {
            Write-Host " You are running the latest version ($CurrentVersion)." -ForegroundColor DarkGreen
        }
    } catch {
        Write-Host " Note: Could not reach GitHub to check for updates." -ForegroundColor DarkGray
    }
}

# Capture Starting Disk Space
$Drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$StartingFreeSpace = $Drive.FreeSpace

# Ensure Log directory exists
if (!(Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }

Write-Host "`n--- Windows System Cleanup Tool ---" -ForegroundColor Cyan
Write-Host "Running from: $CurrentDir" -ForegroundColor Gray
Write-Host "Initial Free Space: $([Math]::Round($StartingFreeSpace / 1GB, 2)) GB" -ForegroundColor Gray

# Run the update check
Check-ForUpdates

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

# --- START TIMER ---
$CleanupTimer = [System.Diagnostics.Stopwatch]::StartNew()

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

    # --- STOP TIMER ---
    $CleanupTimer.Stop()
    $TimeSpan = $CleanupTimer.Elapsed
    $FormattedTime = "{0:mm} min {0:ss} sec" -f $TimeSpan

    # --- FINAL CALCULATION ---
    $DriveEnd = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $EndingFreeSpace = $DriveEnd.FreeSpace
    $SpaceSavedBytes = $EndingFreeSpace - $StartingFreeSpace

    # Check for negative value (background noise)
    if ($SpaceSavedBytes -le 0) {
        $ReadableSpace = "0 MB"
    } elseif ($SpaceSavedBytes -gt 1GB) {
        $ReadableSpace = "$([Math]::Round($SpaceSavedBytes / 1GB, 2)) GB"
    } else {
        $ReadableSpace = "$([Math]::Round($SpaceSavedBytes / 1MB, 2)) MB"
    }

    Write-Host "`n----------------------------------------------------------" -ForegroundColor Green
    Write-Host " SUCCESS: Cleanup process finished!" -ForegroundColor Green
    Write-Host " TOTAL STORAGE RECLAIMED: $ReadableSpace" -ForegroundColor White -BackgroundColor DarkGreen
    Write-Host " TIME ELAPSED: $FormattedTime" -ForegroundColor White
    Write-Host "----------------------------------------------------------" -ForegroundColor Green

} catch {
    $CleanupTimer.Stop()
    $ErrorMessage = "$(Get-Date -Format 'dd-MM-yyyy HH:mm:ss'): $($_.Exception.Message)"
    Add-Content -Path "$LogDir\SystemCleanUpErrors.log" -Value $ErrorMessage
    Write-Host "`nAn error occurred. See $LogDir\SystemCleanUpErrors.log" -ForegroundColor Red
}

Write-Host "Press any key to exit..."
$null = [Console]::ReadKey($true)
Exit