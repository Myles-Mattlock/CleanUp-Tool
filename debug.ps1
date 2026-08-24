# Reliable NVMe Temperature Monitoring Loop
$TempThresholdC = 70

Write-Host "Monitoring NVMe/SSD temperature via StorageReliabilityCounter... (Threshold: ${TempThresholdC}°C)" -ForegroundColor Cyan

while ($true) {
    # Query physical disk reliability data directly from the Windows Storage provider
    $disks = Get-PhysicalDisk | Where-Object { $_.BusType -eq 'NVMe' -or $_.MediaType -eq 'SSD' }
    
    foreach ($disk in $disks) {
        $stats = $disk | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
        if ($stats -and $stats.Temperature) {
            $currentTemp = $stats.Temperature
            Write-Host "Drive [$($disk.FriendlyName)]: ${currentTemp}°C" -ForegroundColor Gray

            if ($currentTemp -ge $TempThresholdC) {
                Write-Warning "ALERT: Drive [$($disk.FriendlyName)] reached ${currentTemp}°C!"
                
                # Audible alert tones
                for ($i = 0; $i -lt 4; $i++) {
                    [Console]::Beep(1200, 150)
                    Start-Sleep -Milliseconds 5
                    [Console]::Beep(800, 150)
                    Start-Sleep -Milliseconds 5
                }
            }
        }
    }

    Start-Sleep -Seconds 5
}