param(
    [Parameter(Mandatory = $true)] [string]$DownloadUrl,
    [Parameter(Mandatory = $true)] [string]$TargetDirectory,
    [Parameter(Mandatory = $true)] [string]$ApplicationPath,
    [Parameter(Mandatory = $true)] [int]$ParentProcessId
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object Windows.Forms.Form
$form.Text = 'System CleanUp Update'
$form.Size = New-Object Drawing.Size(520, 170)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.ControlBox = $false
$form.TopMost = $true

$status = New-Object Windows.Forms.Label
$status.Location = New-Object Drawing.Point(24, 22)
$status.Size = New-Object Drawing.Size(450, 30)
$status.Font = New-Object Drawing.Font('Segoe UI', 10)
$form.Controls.Add($status)

$progress = New-Object Windows.Forms.ProgressBar
$progress.Location = New-Object Drawing.Point(24, 68)
$progress.Size = New-Object Drawing.Size(450, 24)
$progress.Style = 'Marquee'
$progress.MarqueeAnimationSpeed = 25
$form.Controls.Add($progress)
$form.Show()

function Set-UpdateStatus {
    param([string]$Message)
    $status.Text = $Message
    $form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
    Add-Content -LiteralPath $logPath -Value $Message
}

$logPath = Join-Path ([System.IO.Path]::GetTempPath()) 'SystemCleanUpUpdater.log'
$zipPath = Join-Path ([System.IO.Path]::GetTempPath()) 'SystemCleanUpUpdate.zip'
$extractPath = Join-Path ([System.IO.Path]::GetTempPath()) 'SystemCleanUpUpdate'

try {
    if ($DownloadUrl -notmatch '/releases/download/[^/]+/SystemCleanUp\.zip$') {
        throw 'DownloadUrl must be the direct SystemCleanUp.zip release asset URL, not the GitHub release page.'
    }
    if (-not (Test-Path -LiteralPath $TargetDirectory -PathType Container)) {
        throw "Target directory was not found: $TargetDirectory"
    }
    if ([System.IO.Path]::GetExtension($ApplicationPath) -ne '.exe') {
        throw "ApplicationPath must point to System CleanUp.exe: $ApplicationPath"
    }
    Set-Content -LiteralPath $logPath -Value 'Updater started.'
    Set-UpdateStatus 'Downloading update package...'
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $zipPath -UseBasicParsing
    Set-UpdateStatus 'Extracting update package...'
    Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extractPath)

    $payload = Join-Path $extractPath 'SystemCleanUp'
    $newApplication = Join-Path $payload 'System CleanUp.exe'
    if (-not (Test-Path $newApplication)) {
        throw 'The release ZIP does not contain SystemCleanUp\System CleanUp.exe.'
    }

    Set-UpdateStatus "Waiting for System CleanUp to close..."
    Add-Content -LiteralPath $logPath -Value "Target directory: $TargetDirectory"
    Add-Content -LiteralPath $logPath -Value "Application path: $ApplicationPath"
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Process -Id $ParentProcessId -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 250
    }
    if (Get-Process -Id $ParentProcessId -ErrorAction SilentlyContinue) {
        throw 'The application did not exit within 30 seconds.'
    }

    Set-UpdateStatus 'Installing updated application files...'
    if (-not (Test-Path $TargetDirectory)) { New-Item -ItemType Directory -Path $TargetDirectory -Force | Out-Null }
    $files = Get-ChildItem -LiteralPath $payload -Force
    foreach ($file in $files) {
        $destination = Join-Path $TargetDirectory $file.Name
        if ($file.PSIsContainer) {
            Copy-Item -LiteralPath $file.FullName -Destination $destination -Recurse -Force -ErrorAction Stop
        } else {
            Copy-Item -LiteralPath $file.FullName -Destination $destination -Force -ErrorAction Stop
        }
        Set-UpdateStatus "Installing $($file.Name)..."
    }
    Unblock-File -LiteralPath $ApplicationPath -ErrorAction SilentlyContinue
    Set-UpdateStatus 'Starting updated application...'
    Start-Process -FilePath $ApplicationPath
    $status.Text = 'Update complete.'
    $progress.Style = 'Continuous'
    $progress.Value = 100
    $form.Refresh()
    Start-Sleep -Milliseconds 500
} catch {
    Add-Content -LiteralPath $logPath -Value "Update failed: $($_.Exception.Message)"
    $status.Text = "Update failed: $($_.Exception.Message)"
    $progress.Style = 'Continuous'
    $progress.Value = 0
    $form.ControlBox = $true
    $form.Refresh()
    [System.Windows.Forms.MessageBox]::Show("Update failed: $($_.Exception.Message)`n`nLog: $logPath", 'System CleanUp Update', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
} finally {
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
    $form.Close()
}
