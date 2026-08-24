function Update-DriveHealthAndTemp {
    try {
        $PhysicalDisks = Get-PhysicalDisk -ErrorAction SilentlyContinue
        foreach ($Disk in $PhysicalDisks) {
            $TempStr = "N/A"
            $HealthStr = "Healthy"

            # 1. Query Direct NVMe Byte 05 using the disk's actual physical Index
            $DirectHealth = [NVMeSmartReader]::GetNVMePercentageUsed([int]$Disk.DeviceId)
            if ($DirectHealth -ge 0) {
                $HealthStr = "$DirectHealth% Health"
            } else {
                # Fallback to standard status if NVMe byte fails or is SATA
                if ($Disk.HealthStatus) { $HealthStr = $Disk.HealthStatus }
            }

            # 2. Temperature check via StorageReliabilityCounter
            try {
                $Counter = $Disk | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
                if ($Counter -and $Counter.Temperature -gt 0 -and $Counter.Temperature -lt 120) {
                    $TempStr = "$($Counter.Temperature) °C"
                }
            } catch {}

            # Map Physical Disk Number to Volume Drive Letters
            $DiskObj = Get-Disk | Where-Object { $_.Number -eq $Disk.DeviceId -or $_.UniqueId -eq $Disk.UniqueId } -ErrorAction SilentlyContinue
            if ($DiskObj) {
                $Partitions = $DiskObj | Get-Partition -ErrorAction SilentlyContinue
                foreach ($Part in $Partitions) {
                    if ($Part.DriveLetter) {
                        $Key = "$($Part.DriveLetter):"
                        if ($Global:DriveUIMap.ContainsKey($Key)) {
                            $Global:DriveUIMap[$Key].Health.Text = $HealthStr
                            $Global:DriveUIMap[$Key].Temp.Text   = $TempStr
                        }
                    }
                }
            }
        }
    } catch {}
}