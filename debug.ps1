Clear-Host
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "    STORAGE TELEMETRY DEBUG TEST - PART 2" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# METHOD: Map Physical Disk -> Drive Letter -> Health & Temp
$PhysicalDisks = Get-PhysicalDisk -ErrorAction SilentlyContinue

foreach ($Disk in $PhysicalDisks) {
    Write-Host "`n--------------------------------------------------" -ForegroundColor Gray
    Write-Host "Physical Disk Index $($Disk.DeviceId) - $($Disk.FriendlyName)" -ForegroundColor Green

    # 1. Health Math Fix (Wear = 0 means 100% Health)
    $HealthText = "Healthy"
    $TempText   = "N/A"

    try {
        $Counter = $Disk | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
        if ($Counter) {
            # Temp Check
            if ($Counter.Temperature -gt 0) {
                $TempText = "$($Counter.Temperature) °C"
            }

            # Wear / Health Math Check
            if ($null -ne $Counter.Wear -and $Counter.Wear -ne "") {
                $HealthValue = 100 - [int]$Counter.Wear
                $HealthText  = "$HealthValue% Health"
            }
        }
    } catch {
        Write-Host "  Error reading reliability counter: $_" -ForegroundColor Red
    }

    Write-Host "  Calculated Health Display: $HealthText" -ForegroundColor Yellow
    Write-Host "  Calculated Temp Display:   $TempText" -ForegroundColor Yellow

    # 2. Drive Letter Mapping Fix (using Get-Disk instead of Get-Partition -DiskNumber)
    try {
        $DiskObj = Get-Disk | Where-Object { $_.Number -eq $Disk.DeviceId -or $_.UniqueId -eq $Disk.UniqueId } -ErrorAction SilentlyContinue
        if ($DiskObj) {
            $Partitions = $DiskObj | Get-Partition -ErrorAction SilentlyContinue
            foreach ($Part in $Partitions) {
                if ($Part.DriveLetter) {
                    Write-Host "  ===> Maps to Drive Letter: [$($Part.DriveLetter):]" -ForegroundColor Cyan
                }
            }
        } else {
            Write-Host "  [!] Could not map disk to Get-Disk object" -ForegroundColor Red
        }
    } catch {
        Write-Host "  [!] Partition mapping error: $_" -ForegroundColor Red
    }
}

Write-Host "`n==================================================" -ForegroundColor Cyan