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

# Capture Starting Disk Space
$Drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$StartingFreeSpace = $Drive.FreeSpace

# Ensure Log directory exists
if (!(Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }

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

} catch {
    $ErrorMessage = "$(Get-Date -Format 'dd-MM-yyyy HH:mm:ss'): $($_.Exception.Message)"
    Add-Content -Path "$LogDir\SystemCleanUpErrors.log" -Value $ErrorMessage
    Write-Host "`nAn error occurred. See $LogDir\SystemCleanUpErrors.log" -ForegroundColor Red
}