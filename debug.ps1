Clear-Host
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "    NVME TELEMETRY DEBUG TEST (REFINED)" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# --- TEST 1: MSFT_PhysicalDisk StorageReliabilityCounter via CIM Direct ---
Write-Host "`n[TEST 1] Querying CIM StorageReliabilityCounter per disk instance..." -ForegroundColor Yellow

$PhysicalDisks = Get-CimInstance -Namespace "root\microsoft\windows\storage" -ClassName "MSFT_PhysicalDisk" -ErrorAction SilentlyContinue

foreach ($Disk in $PhysicalDisks) {
    Write-Host "`nDisk $($Disk.DeviceId) - $($Disk.FriendlyName):" -ForegroundColor Green
    
    # Query reliability counter associated with this specific disk object
    $Counter = Get-CimInstance -Namespace "root\microsoft\windows\storage" -ClassName "MSFT_StorageReliabilityCounter" -ErrorAction SilentlyContinue | Where-Object { $_.DeviceId -eq $Disk.DeviceId }
    
    if ($Counter) {
        Write-Host "  Raw Temperature: $($Counter.Temperature)" -ForegroundColor Cyan
        Write-Host "  Wear Percentage: $($Counter.Wear)" -ForegroundColor Cyan
        
        # Calculate display strings
        $TempStr = if ($Counter.Temperature -gt 0 -and $Counter.Temperature -lt 120) { "$($Counter.Temperature) °C" } else { "N/A" }
        $HealthStr = if ($null -ne $Counter.Wear) { "$(100 - [int]$Counter.Wear)% Health" } else { "Healthy" }
        
        Write-Host "  => Health Display: $HealthStr" -ForegroundColor Green
        Write-Host "  => Temp Display:   $TempStr" -ForegroundColor Green
    } else {
        Write-Host "  [!] No reliability counter found for DeviceId $($Disk.DeviceId)" -ForegroundColor Red
    }
}

# --- TEST 2: MSFT_Disk / Storage Reliability via WMI Association ---
Write-Host "`n`n[TEST 2] Checking StorageReliabilityCounter via WMI Associators..." -ForegroundColor Yellow
Get-CimInstance Win32_DiskDrive | ForEach-Object {
    $Disk = $_
    Write-Host "`nWin32_DiskDrive Index $($Disk.Index) ($($Disk.Model)):" -ForegroundColor Green
    
    # Associate physical drive to logical partitions & drive letters
    $Partitions = Get-CimInstance -Query "ASSOCIATORS OF {Win32_DiskDrive.DeviceID='$($Disk.DeviceID.Replace('\','\\'))'} WHERE AssocClass = Win32_DiskDriveToDiskPartition" -ErrorAction SilentlyContinue
    foreach ($Part in $Partitions) {
        $LogicalDisks = Get-CimInstance -Query "ASSOCIATORS OF {Win32_DiskPartition.DeviceID='$($Part.DeviceID)'} WHERE AssocClass = Win32_LogicalDiskToPartition" -ErrorAction SilentlyContinue
        foreach ($LogDisk in $LogicalDisks) {
            Write-Host "  ===> Volume Letter: [$($LogDisk.DeviceID)]" -ForegroundColor Cyan
        }
    }
}

Write-Host "`n==================================================" -ForegroundColor Cyan