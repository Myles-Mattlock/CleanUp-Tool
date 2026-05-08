# --- Configuration ---
$FolderName      = "SystemCleanUp"
# Gets the directory where the EXE is currently sitting
$CurrentDir      = $PSScriptRoot
if ([string]::IsNullOrEmpty($CurrentDir)) { $CurrentDir = Get-Location }

$SourcePath      = Join-Path -Path $CurrentDir -ChildPath $FolderName
$TargetPath      = Join-Path -Path $env:ProgramFiles -ChildPath $FolderName

# Shortcut Settings
$shortcutName    = "System CleanUp"
$exeName         = "System CleanUp.exe" 
$executablePath  = Join-Path -Path $TargetPath -ChildPath $exeName
$ProcessName     = "System CleanUp"

# --- Execution ---
Write-Host "Starting installation..." -ForegroundColor Cyan

# 0. Kill process if running to prevent "File in Use" errors
if (Get-Process -Name $ProcessName -ErrorAction SilentlyContinue) {
    Write-Host "Closing running instance of $ProcessName..." -ForegroundColor Yellow
    Stop-Process -Name $ProcessName -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

# 1. Check if Source Folder exists next to this EXE
if (-not (Test-Path -Path $SourcePath)) {
    Write-Error "Source folder '$FolderName' not found at $SourcePath"
    Pause
    exit
}

# 2. Clear old files
if (Test-Path -Path $TargetPath) {
    Write-Host "Removing old version..." -ForegroundColor Yellow
    try {
        Remove-Item -Path "$TargetPath\*" -Recurse -Force -ErrorAction Stop
    }
    catch {
        Write-Error "Failed to clear directory. Is the app still open? Error: $($_.Exception.Message)"
        Pause
        exit
    }
} else {
    New-Item -ItemType Directory -Path $TargetPath -Force | Out-Null
}

# 3. Copy files
try {
    Write-Host "Installing to $TargetPath..." -ForegroundColor White
    Copy-Item -Path "$SourcePath\*" -Destination $TargetPath -Recurse -Force -ErrorAction Stop
    
    # Unblock the files so Windows doesn't show security warnings
    Get-ChildItem -Path $TargetPath -Recurse | Unblock-File
}
catch {
    Write-Error "Copy failed: $($_.Exception.Message)"
    Pause
    exit
}

# 4. Create Desktop Shortcut
try {
    $desktopPath = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop)
    $shortcutPath = Join-Path $desktopPath "$shortcutName.lnk"
    $WshShell = New-Object -ComObject WScript.Shell
    $shortcut = $WshShell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $executablePath
    $shortcut.WorkingDirectory = $TargetPath
    $shortcut.Description = "Clean up Windows using Myles' Tool"
    $shortcut.Save()
    Write-Host "Shortcut created on Desktop." -ForegroundColor Green
}
catch {
    Write-Warning "Shortcut could not be created."
}

Write-Host "Installation successful!" -ForegroundColor Green
Start-Sleep -Seconds 3