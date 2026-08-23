Get-PhysicalDisk | ForEach-Object {
    $Disk = $_
    $Counter = $Disk | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
    [PSCustomObject]@{
        FriendlyName = $Disk.FriendlyName
        DeviceId     = $Disk.DeviceId
        Operational  = $Disk.OperationalStatus
        HealthStatus = $Disk.HealthStatus
        Temp_C       = if ($Counter.Temperature) { $Counter.Temperature } else { "N/A" }
        WearPercent  = if ($Counter.Wear) { $Counter.Wear } else { "N/A" }
    }
}