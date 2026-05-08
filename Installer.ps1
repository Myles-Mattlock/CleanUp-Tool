# --- Configuration ---
$FolderName      = "SystemCleanUp"
$SourcePath      = Join-Path -Path $PSScriptRoot -ChildPath $FolderName
$TargetPath      = Join-Path -Path $env:ProgramFiles -ChildPath $FolderName

# Shortcut Settings
$shortcutName    = "System CleanUp"
$exeName         = "SystemCleanUp.exe" # Ensure this matches your actual EXE filename
$executablePath  = Join-Path -Path $TargetPath -ChildPath $exeName

# --- Execution ---
Write-Host "Starting installation of $FolderName..." -ForegroundColor Cyan

# 1. Check if Source Folder exists
if (-not (Test-Path -Path $SourcePath)) {
    Write-Error "Source folder '$FolderName' not found in the current directory."
    Pause
    exit
}

# 2. Handle existing installation (Replace logic)
if (Test-Path -Path $TargetPath) {
    Write-Host "Existing installation found. Removing old files..." -ForegroundColor Yellow
    try {
        Remove-Item -Path "$TargetPath\*" -Recurse -Force -ErrorAction Stop
    }
    catch {
        Write-Error "Could not clear existing folder. Ensure no files are in use."
        Pause
        exit
    }
} else {
    Write-Host "Creating destination directory..." -ForegroundColor Gray
    New-Item -ItemType Directory -Path $TargetPath -Force | Out-Null
}

# 3. Copy new files
try {
    Write-Host "Copying files to $TargetPath..." -ForegroundColor White
    Copy-Item -Path "$SourcePath\*" -Destination $TargetPath -Recurse -Force -ErrorAction Stop
}
catch {
    Write-Error "Installation failed: $($_.Exception.Message)"
    Pause
    exit
}

# 4. Unblock Files
# This removes the "Mark of the Web" so the user isn't prompted with security warnings
try {
    Write-Host "Unblocking files to prevent security warnings..." -ForegroundColor Cyan
    Get-ChildItem -Path $TargetPath -Recurse | Unblock-File
}
catch {
    Write-Warning "Could not unblock some files, but installation will continue."
}

# 5. Create Desktop Shortcut
try {
    Write-Host "Creating desktop shortcut..." -ForegroundColor Cyan
    $desktopPath = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop)
    $shortcutPath = Join-Path $desktopPath "$shortcutName.lnk"
    
    $WshShell = New-Object -ComObject WScript.Shell
    $shortcut = $WshShell.CreateShortcut($shortcutPath)
    
    $shortcut.TargetPath = $executablePath
    $shortcut.WorkingDirectory = $TargetPath
    $shortcut.Description = "Clean up Windows using Myles' Tool"
    $shortcut.Save()

    Write-Host "Shortcut for '$shortcutName' created successfully on the desktop." -ForegroundColor Green
}
catch {
    Write-Warning "Files copied and unblocked, but failed to create shortcut: $($_.Exception.Message)"
}

Write-Host "Installation completed successfully!" -ForegroundColor Green
Pause