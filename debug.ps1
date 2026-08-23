Clear-Host
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "    STORAGE TELEMETRY DEBUG TEST - PART 3" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

$PhysicalDisks = Get-PhysicalDisk -ErrorAction SilentlyContinue

foreach ($Disk in $PhysicalDisks) {
    Write-Host "`n--------------------------------------------------" -ForegroundColor Gray
    Write-Host "Physical Disk Index $($Disk.DeviceId) - $($Disk.FriendlyName)" -ForegroundColor Green

    $HealthText = "Healthy"
    $TempText   = "N/A"

    try {
        $Counter = $Disk | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
        if ($Counter) {
            # Temp check
            if ($Counter.Temperature -gt 0 -and $Counter.Temperature -lt 120) {
                $TempText = "$($Counter.Temperature) °C"
            }

            # Explicit null/type check for Wear
            if ($PSItem -ne $null -and $null -ne $Counter.Wear) {
                $WearInt = [int]$Counter.Wear
                $HealthValue = 100 - $WearInt
                $HealthText  = "$HealthValue% Health"
                Write-Host "  Raw Wear Value Read: $WearInt%" -ForegroundColor Gray
            }
        }
    } catch {
        Write-Host "  Error reading counter: $_" -ForegroundColor Red
    }

    Write-Host "  Calculated Health Display: $HealthText" -ForegroundColor Yellow
    Write-Host "  Calculated Temp Display:   $TempText" -ForegroundColor Yellow

    # Drive mapping
    $DiskObj = Get-Disk | Where-Object { $_.Number -eq $Disk.DeviceId -or $_.UniqueId -eq $Disk.UniqueId } -ErrorAction SilentlyContinue
    if ($DiskObj) {
        $Partitions = $DiskObj | Get-Partition -ErrorAction SilentlyContinue
        foreach ($Part in $Partitions) {
            if ($Part.DriveLetter) {
                Write-Host "  ===> Maps to Drive Letter: [$($Part.DriveLetter):]" -ForegroundColor Cyan
            }
        }
    }
}

Write-Host "`n==================================================" -ForegroundColor Cyan