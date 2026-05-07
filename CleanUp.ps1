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
$CurrentVersion = "v1.3.0" 
$RepoName = "Myles-Mattlock/CleanUp-Tool"
$RegFiles = @("DiskCleanupSettings.reg", "DiskCleanupSettings2.reg") 
$LogDir = "C:\Logs"
# ---------------------

# --- UPDATE CHECKER (DEBUG VERSION) ---
function Check-ForUpdates {
    Write-Host "Checking for updates..." -ForegroundColor Gray
    try {
        # Force Protocols
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
        
        $UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) PowerShell-App"
        $Url = "https://api.github.com/repos/$RepoName/releases"

        # ATTEMPT FETCH
        $Releases = Invoke-RestMethod -Uri $Url -Method Get -UserAgent $UserAgent -ErrorAction Stop
        
        $CurrentVerObj = [System.Management.Automation.SemanticVersion]($CurrentVersion.TrimStart('v'))
        $LatestRelease = $Releases | ForEach-Object {
            try {
                [PSCustomObject]@{
                    Version = [System.Management.Automation.SemanticVersion]($_.tag_name.TrimStart('v'))
                    Url     = $_.html_url
                    Tag     = $_.tag_name
                    IsBeta  = $_.prerelease
                }
            } catch { $null }
        } | Sort-Object Version -Descending | Select-Object -First 1

        if ($LatestRelease -and ($LatestRelease.Version -gt $CurrentVerObj)) {
            Write-Host "----------------------------------------------------------" -ForegroundColor Cyan
            Write-Host " [!] NEW VERSION AVAILABLE: $($LatestRelease.Tag)" -ForegroundColor White -BackgroundColor Blue
            Write-Host " Download: $($LatestRelease.Url)" -ForegroundColor Cyan
            Write-Host "----------------------------------------------------------" -ForegroundColor Cyan
        } else {
            Write-Host " You are running the latest version." -ForegroundColor DarkGreen
        }
    } catch {
        Write-Host "`n--- UPDATE DEBUG INFO ---" -ForegroundColor Red
        Write-Host "Error Type: $($_.Exception.GetType().FullName)" -ForegroundColor Yellow
        Write-Host "Message: $($_.Exception.Message)" -ForegroundColor White
        
        # Check if it's a web exception to get the status code
        if ($_.Exception.InnerException -and $_.Exception.InnerException.Response) {
            $StatusCode = [int]$_.Exception.InnerException.Response.StatusCode
            Write-Host "HTTP Status Code: $StatusCode" -ForegroundColor Yellow
        }

        # Check .NET Runtime version the EXE is using
        $Runtime = [Runtime.InteropServices.RuntimeInformation]::FrameworkDescription
        Write-Host "Running on: $Runtime" -ForegroundColor Gray
        Write-Host "--------------------------`n" -ForegroundColor Red
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

# 4. User Confirmation
Write-Host ""
$Confirmation = Read-Host "Begin system cleanup? (Y/N)"
if ($Confirmation -notmatch "y|yes") {
    Write-Host "Operation cancelled." -ForegroundColor Red
    Start-Sleep -Seconds 2
    Exit
}

# (The rest of your cleanup code remains the same...)
Write-Host "Cleaning..."
# ... [Omitted for brevity, use your existing cleanup logic here] ...

Write-Host "Press any key to exit..."
$null = [Console]::ReadKey($true)
Exit