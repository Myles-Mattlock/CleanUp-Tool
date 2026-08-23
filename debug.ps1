Clear-Host
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "    STORAGE TELEMETRY DEBUG TEST" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# METHOD 1: StorageReliabilityCounter (Standard Windows Storage API)
Write-Host "`n--- METHOD 1: Get-StorageReliabilityCounter ---" -ForegroundColor Yellow
$PhysicalDisks = Get-PhysicalDisk -ErrorAction SilentlyContinue
foreach ($Disk in $PhysicalDisks) {
    Write-Host "`nDisk Index $($Disk.DeviceId) - $($Disk.FriendlyName):" -ForegroundColor Green
    Write-Host "  HealthStatus (WMI): $($Disk.HealthStatus)"
    Write-Host "  OperationalStatus:  $($Disk.OperationalStatus)"
    
    try {
        $Counter = $Disk | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
        if ($Counter) {
            Write-Host "  [Reliability Counter Found]" -ForegroundColor Gray
            Write-Host "  - Raw Temperature:  $($Counter.Temperature)"
            Write-Host "  - Wear Percentage:  $($Counter.Wear)"
            Write-Host "  - Read Errors Total:$($Counter.ReadErrorsTotal)"
        } else {
            Write-Host "  [!] StorageReliabilityCounter returned NULL" -ForegroundColor Red
        }
    } catch {
        Write-Host "  [!] Exception reading Reliability Counter: $_" -ForegroundColor Red
    }
}

# METHOD 2: Direct WMI MSFT_PhysicalDisk & StorageReliabilityCounter Class Queries
Write-Host "`n--- METHOD 2: Direct CIM/WMI Class Queries ---" -ForegroundColor Yellow
try {
    $CimCounters = Get-CimInstance -Namespace "root\microsoft\windows\storage" -ClassName "MSFT_StorageReliabilityCounter" -ErrorAction SilentlyContinue
    foreach ($C in $CimCounters) {
        Write-Host "CIM DeviceId: $($C.DeviceId) | Temp: $($C.Temperature) | Wear: $($C.Wear)"
    }
} catch {
    Write-Host "  [!] CIM Query Failed: $_" -ForegroundColor Red
}

# METHOD 3: Partition to Disk Mapping
Write-Host "`n--- METHOD 3: Partition to Drive Letter Association ---" -ForegroundColor Yellow
foreach ($Disk in $PhysicalDisks) {
    $Parts = Get-Partition -DiskNumber $Disk.DiskNumber -ErrorAction SilentlyContinue
    foreach ($P in $Parts) {
        if ($P.DriveLetter) {
            Write-Host "Physical Disk $($Disk.DeviceId) ($($Disk.FriendlyName)) ===> Drive Letter $($P.DriveLetter):" -ForegroundColor Cyan
        }
    }
}

Write-Host "`n==================================================" -ForegroundColor Cyan