# Set your target temperature threshold (°C)
$TempThresholdC = 70

Write-Host "Monitoring NVMe/SSD temperature... (Threshold: ${TempThresholdC}°C)" -ForegroundColor Cyan

while ($true) {
    # Query MSStorageDriver_FailurePredictData / Storage WMI classes
    $drives = Get-CimInstance -Namespace "root\wmi" -ClassName "MSStorageDriver_FailurePredictData" -ErrorAction SilentlyContinue

    $overheating = $false

    foreach ($drive in $drives) {
        # Extract SMART Attribute 194 or 190 (Temperature)
        $vendorData = $drive.VendorSpecific
        if ($vendorData.Length -ge 12) {
            # Temperature byte location in standard SMART payload
            $currentTemp = $vendorData[5] 
            
            if ($currentTemp -ge $TempThresholdC -and $currentTemp -lt 125) {
                $overheating = $true
                Write-Warning "SSD Alert! Drive temperature reached ${currentTemp}°C"
            }
        }
    }

    if ($overheating) {
        # Trigger Warning Tone
        for ($i = 0; $i -lt 3; $i++) {
            [Console]::Beep(1200, 120)
            [Console]::Beep(800, 120)
        }
    }

    Start-Sleep -Seconds 5
}