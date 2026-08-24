Clear-Host
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "    SMARTCTL JSON TELEMETRY DEBUG TEST" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

$CurrentDir = if ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { Get-Location }
$SmartctlPath = Join-Path $CurrentDir "smartctl.exe"

if (-not (Test-Path $SmartctlPath)) {
    Write-Host "[!] ERROR: smartctl.exe not found in $CurrentDir" -ForegroundColor Red
    Exit
}

Get-PhysicalDisk | ForEach-Object {
    $Disk = $_
    Write-Host "`nTesting Physical Disk [$($Disk.DeviceId)] - $($Disk.FriendlyName)..." -ForegroundColor Yellow

    try {
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo -Property @{
            FileName               = $SmartctlPath
            Arguments              = "-j -a /dev/pd$($Disk.DeviceId)"
            UseShellExecute        = $false
            RedirectStandardOutput = $true
            CreateNoWindow         = $true
        }
        $p = [System.Diagnostics.Process]::Start($pinfo)
        $Output = $p.StandardOutput.ReadToEnd()
        $p.WaitForExit()

        if (-not [string]::IsNullOrWhiteSpace($Output)) {
            $Json = $Output | ConvertFrom-Json
            
            # Extract Temp
            $TempStr = "N/A"
            if ($Json.temperature.current) {
                $TempStr = "$($Json.temperature.current) °C"
            } elseif ($Json.nvme_smart_health_information_log.temperature) {
                $TempStr = "$($Json.nvme_smart_health_information_log.temperature) °C"
            }

            # Extract Wear / Health
            $HealthStr = "Healthy"
            if ($null -ne $Json.nvme_smart_health_information_log.percentage_used) {
                $Used = [int]$Json.nvme_smart_health_information_log.percentage_used
                $HealthStr = "$(100 - $Used)% Health"
            } elseif ($Json.smart_status.passed -eq $true) {
                $HealthStr = "100% Health"
            }

            Write-Host "  [SUCCESS] Parsed Health: $HealthStr" -ForegroundColor Green
            Write-Host "  [SUCCESS] Parsed Temp:   $TempStr" -ForegroundColor Green
        } else {
            Write-Host "  [FAIL] smartctl returned empty output." -ForegroundColor Red
        }
    } catch {
        Write-Host "  [FAIL] Error executing smartctl: $_" -ForegroundColor Red
    }
}

Write-Host "`n==================================================" -ForegroundColor Cyan