Clear-Host
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "    SAFE STORAGE TELEMETRY FALLBACK TEST" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

$DriveMap = @{}

# Fetch physical drives and map health / temp cleanly
Get-PhysicalDisk | ForEach-Object {
    $Disk = $_
    $HealthDisplay = if ($Disk.HealthStatus -eq "Healthy") { "Healthy" } else { $Disk.HealthStatus }
    $TempDisplay   = "N/A"

    # Try reading counter if available
    try {
        $Counter = $Disk | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
        if ($Counter) {
            if ($Counter.Temperature -gt 0 -and $Counter.Temperature -lt 120) {
                $TempDisplay = "$($Counter.Temperature) °C"
            }
            if ($null -ne $Counter.Wear) {
                $HealthDisplay = "$(100 - [int]$Counter.Wear)% Health"
            }
        }
    } catch {}

    # Map physical disk to drive letters using Get-Disk & Get-Partition
    $DiskObj = Get-Disk | Where-Object { $_.Number -eq $Disk.DeviceId -or $_.UniqueId -eq $Disk.UniqueId } -ErrorAction SilentlyContinue
    if ($DiskObj) {
        $Partitions = $DiskObj | Get-Partition -ErrorAction SilentlyContinue
        foreach ($Part in $Partitions) {
            if ($Part.DriveLetter) {
                $Letter = "$($Part.DriveLetter):"
                Write-Host "`nFound Drive [$Letter] on Physical Disk $($Disk.DeviceId) ($($Disk.FriendlyName))" -ForegroundColor Green
                Write-Host "  Mapped Health: $HealthDisplay" -ForegroundColor Yellow
                Write-Host "  Mapped Temp:   $TempDisplay" -ForegroundColor Yellow
            }
        }
    }
}

Write-Host "`n==================================================" -ForegroundColor Cyan