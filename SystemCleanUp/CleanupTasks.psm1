Set-StrictMode -Version Latest

function Get-CleanupTargetPaths {
    @(
        (Join-Path $env:WINDIR "Temp\*"),
        (Join-Path $env:WINDIR "Prefetch\*"),
        (Join-Path $env:WINDIR "SoftwareDistribution\Download\*"),
        "$([System.IO.Path]::GetTempPath())*",
        (Join-Path $env:SystemDrive "Intel"),
        (Join-Path $env:SystemDrive "PerfLogs")
    )
}

function Get-CleanupProgress {
    param(
        [int]$Completed,
        [int]$Total
    )

    if ($Total -le 0) {
        return 100
    }

    [Math]::Min(100, [Math]::Max(0, [Math]::Round(($Completed / $Total) * 100)))
}

function Invoke-CleanupProcess {
    param(
        [Parameter(Mandatory)]
        [string]$FileName,
        [string]$Arguments = ""
    )

    $process = $null
    try {
        $processInfo = [System.Diagnostics.ProcessStartInfo]@{
            FileName               = $FileName
            Arguments              = $Arguments
            UseShellExecute        = $false
            RedirectStandardOutput = $true
            RedirectStandardError  = $true
            CreateNoWindow         = $true
        }

        $process = [System.Diagnostics.Process]::Start($processInfo)
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()

        $result = [pscustomobject]@{
            FileName = $FileName
            ExitCode = $process.ExitCode
            Output   = $stdoutTask.Result
            Error    = $stderrTask.Result
            Success  = $process.ExitCode -eq 0
        }

        return $result
    }
    catch {
        return [pscustomobject]@{
            FileName = $FileName
            ExitCode = -1
            Output   = ""
            Error    = $_.Exception.Message
            Success  = $false
        }
    }
    finally {
        if ($null -ne $process) {
            $process.Dispose()
        }
    }
}

function Write-CleanupError {
    param(
        [Parameter(Mandatory)]
        [string]$LogDirectory,
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    New-Item -Path $LogDirectory -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    $message = "{0}: {1}" -f (Get-Date -Format "dd-MM-yyyy HH:mm:ss"), $ErrorRecord.Exception.Message
    Add-Content -Path (Join-Path $LogDirectory "SystemCleanUpErrors.log") -Value $message
}

Export-ModuleMember -Function Get-CleanupTargetPaths, Get-CleanupProgress, Invoke-CleanupProcess, Write-CleanupError
