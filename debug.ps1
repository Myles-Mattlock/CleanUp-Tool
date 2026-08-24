Clear-Host
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "    NVME THERMAL & THROTTLE TELEMETRY TEST" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# Locate smartctl in PATH, Winget directory, or current folder
$SmartctlPath = Get-Command "smartctl.exe" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
if (-not $SmartctlPath) {
    $Candidates = @(
        (Join-Path $PSScriptRoot "smartctl.exe"),
        "C:\Program Files\smartmontools\bin\smartctl.exe",
        "C:\Program Files (x86)\smartmontools\bin\smartctl.exe"
    )
    foreach ($Path in $Candidates) {
        if (Test-Path $Path) { $SmartctlPath = $Path; break }
    }
}

if (-not $SmartctlPath) {
    Write-Host "[!] ERROR: smartctl.exe could not be found." -ForegroundColor Red
    Exit
}

Get-PhysicalDisk | ForEach-Object {
    $Disk = $_
    Write-Host "`n--------------------------------------------------" -ForegroundColor Gray
    Write-Host "Disk [$($Disk.DeviceId)] - $($Disk.FriendlyName)" -ForegroundColor Green

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
            $Log = $Json.nvme_smart_health_information_log

            if ($Log) {
                # Current Temp
                $CurrentTemp = $Log.temperature
                Write-Host "  Current Temperature:          $CurrentTemp °C" -ForegroundColor Yellow

                # Thermal Throttle Counters
                $WarnTime = $Log.warning_composite_temperature_time
                $CritTime = $Log.critical_composite_temperature_time

                if ($null -ne $WarnTime) {
                    $WarnColor = if ($WarnTime -gt 0) { "Red" } else { "Cyan" }
                    Write-Host "  Warning Thermal Throttle Time: $WarnTime Minutes" -ForegroundColor $WarnColor
                }
                if ($null -ne $CritTime) {
                    $CritColor = if ($CritTime -gt 0) { "Red" } else { "Cyan" }
                    Write-Host "  Critical Thermal Throttle Time:$CritTime Minutes" -ForegroundColor $CritColor
                }

                # Health & Spare Check
                if ($null -ne $Log.available_spare) {
                    Write-Host "  Available Reserve Spare:      $($Log.available_spare)%" -ForegroundColor Cyan
                }
            } else {
                # SATA / Non-NVMe Fallback Display
                $Temp = $Json.temperature.current
                if ($Temp) {
                    Write-Host "  Current Temperature (SATA):   $Temp °C" -ForegroundColor Yellow
                } else {
                    Write-Host "  [!] Thermal counters not supported on this interface/drive." -ForegroundColor DarkGray
                }
            }
        }
    } catch {
        Write-Host "  [!] Error parsing drive telemetry: $_" -ForegroundColor Red
    }
}

Write-Host "`n==================================================" -ForegroundColor Cyan