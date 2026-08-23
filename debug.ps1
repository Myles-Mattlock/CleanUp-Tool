Clear-Host
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "    DEEP STORAGE TELEMETRY INSPECTOR" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

$PhysicalDisks = Get-PhysicalDisk -ErrorAction SilentlyContinue

foreach ($Disk in $PhysicalDisks) {
    Write-Host "`n--------------------------------------------------" -ForegroundColor Gray
    Write-Host "Disk Index $($Disk.DeviceId): $($Disk.FriendlyName)" -ForegroundColor Green

    # 1. Inspect all raw properties on StorageReliabilityCounter
    $Counter = $Disk | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
    if ($Counter) {
        Write-Host "`n[Raw StorageReliabilityCounter Properties]:" -ForegroundColor Yellow
        $Counter.PSObject.Properties | ForEach-Object {
            if ($_.Value -ne $null -and $_.Value -ne "") {
                Write-Host "  $($_.Name) = $($_.Value)"
            }
        }
    }

    # 2. Inspect MSFT_PhysicalDisk properties
    Write-Host "`n[Raw PhysicalDisk Properties]:" -ForegroundColor Yellow
    Write-Host "  HealthStatus      = $($Disk.HealthStatus)"
    Write-Host "  OperationalStatus = $($Disk.OperationalStatus)"
    Write-Host "  AllocatedSize     = $($Disk.AllocatedSize)"

    # 3. Check for MSFT_PhysicalDiskStorageNode / StorageNode telemetry
    try {
        $StorageNode = Get-CimInstance -Namespace "root\microsoft\windows\storage" -ClassName "MSFT_PhysicalDisk" -ErrorAction SilentlyContinue | Where-Object DeviceId -eq $Disk.DeviceId
        if ($StorageNode) {
            Write-Host "`n[CIM MSFT_PhysicalDisk]:" -ForegroundColor Yellow
            Write-Host "  Usage = $($StorageNode.Usage)"
            Write-Host "  OperationalStatus = $($StorageNode.OperationalStatus)"
        }
    } catch {}
}

Write-Host "`n==================================================" -ForegroundColor Cyan