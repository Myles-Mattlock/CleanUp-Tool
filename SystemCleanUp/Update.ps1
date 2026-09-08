param(
    [Parameter(Mandatory = $true)] [string]$DownloadUrl,
    [Parameter(Mandatory = $true)] [string]$TargetDirectory,
    [Parameter(Mandatory = $true)] [string]$ApplicationPath,
    [Parameter(Mandatory = $true)] [int]$ParentProcessId
)

$ErrorActionPreference = 'Stop'
$logPath = Join-Path ([System.IO.Path]::GetTempPath()) 'SystemCleanUpUpdater.log'
$zipPath = Join-Path ([System.IO.Path]::GetTempPath()) 'SystemCleanUpUpdate.zip'
$extractPath = Join-Path ([System.IO.Path]::GetTempPath()) 'SystemCleanUpUpdate'

try {
    Set-Content -LiteralPath $logPath -Value 'Updater started.'
    Add-Content -LiteralPath $logPath -Value 'Downloading release asset.'
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $zipPath -UseBasicParsing
    Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force

    $payload = Join-Path $extractPath 'SystemCleanUp'
    $newApplication = Join-Path $payload 'System CleanUp.exe'
    if (-not (Test-Path $newApplication)) {
        throw 'The release ZIP does not contain SystemCleanUp\System CleanUp.exe.'
    }

    Add-Content -LiteralPath $logPath -Value "Target directory: $TargetDirectory"
    Add-Content -LiteralPath $logPath -Value "Application path: $ApplicationPath"
    Add-Content -LiteralPath $logPath -Value "Waiting for process $ParentProcessId to exit."
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Process -Id $ParentProcessId -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 250
    }
    if (Get-Process -Id $ParentProcessId -ErrorAction SilentlyContinue) {
        throw 'The application did not exit within 30 seconds.'
    }

    Add-Content -LiteralPath $logPath -Value 'Replacing installed files.'
    if (-not (Test-Path $TargetDirectory)) { New-Item -ItemType Directory -Path $TargetDirectory -Force | Out-Null }
    $files = Get-ChildItem -LiteralPath $payload -Force
    foreach ($file in $files) {
        $destination = Join-Path $TargetDirectory $file.Name
        if ($file.PSIsContainer) {
            Copy-Item -LiteralPath $file.FullName -Destination $destination -Recurse -Force -ErrorAction Stop
        } else {
            Copy-Item -LiteralPath $file.FullName -Destination $destination -Force -ErrorAction Stop
        }
        Add-Content -LiteralPath $logPath -Value "Copied $($file.Name)"
    }
    Unblock-File -LiteralPath $ApplicationPath -ErrorAction SilentlyContinue
    Add-Content -LiteralPath $logPath -Value 'Starting updated application.'
    Start-Process -FilePath $ApplicationPath
} catch {
    Add-Content -LiteralPath $logPath -Value "Update failed: $($_.Exception.Message)"
    Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
    [System.Windows.MessageBox]::Show("Update failed: $($_.Exception.Message)", 'System CleanUp Update', 'OK', 'Error') | Out-Null
} finally {
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
}
