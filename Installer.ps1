# --- Configuration ---
$FolderName   = "SystemCleanUp"
$SourcePath   = Join-Path -Path $PSScriptRoot -ChildPath $FolderName
$TargetPath   = Join-Path -Path $env:ProgramFiles -ChildPath $FolderName

# --- Execution ---
Write-Host "Starting installation of $FolderName..." -ForegroundColor Cyan

# 1. Check if Source Folder exists (relative to the script/exe)
if (-not (Test-Path -Path $SourcePath)) {
    Write-Error "Source folder '$FolderName' not found in the current directory."
    Pause
    exit
}

# 2. Handle existing installation (The "Replace" logic)
if (Test-Path -Path $TargetPath) {
    Write-Host "Existing installation found. Removing old files..." -ForegroundColor Yellow
    try {
        # We remove the content first to ensure a clean slate
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
    
    Write-Host "Installation completed successfully!" -ForegroundColor Green
}
catch {
    Write-Error "Installation failed: $($_.Exception.Message)"
}

# Keep window open if running manually; remove if you want it to close instantly
Pause