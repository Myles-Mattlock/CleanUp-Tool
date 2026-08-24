Clear-Host
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "    SSD LIFETIME & POWER METRICS INSPECTOR" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# Locate smartctl in system PATH, Winget directory, or current folder
$SmartctlPath = Get-Command "smartctl.exe" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
if (-not $SmartctlPath) {
    $Candidates = @(
        ".\smartctl.exe",
        "C:\Program Files\smartmontools\bin\smartctl.exe",
        "C:\Program Files (x86)\smartmontools\bin\smartctl.exe"
    )
    foreach ($Path in $Candidates) {
        if (Test-Path $Path) { $SmartctlPath = $Path; break }
    }
}

if (-not $SmartctlPath) {
    Write-Host "[!] ERROR: smartctl.exe could not be found." -ForegroundColor Red
    Exit
}

$Results = @()

Get-PhysicalDisk | ForEach-Object {
    $Disk = $_
    $DiskIndex = $Disk.DeviceId

    try {
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo -Property @{
            FileName               = $SmartctlPath
            Arguments              = "-j -a /dev/pd$DiskIndex"
            UseShellExecute        = $false
            RedirectStandardOutput = $true
            CreateNoWindow         = $true
        }
        $p = [System.Diagnostics.Process]::Start($pinfo)
        $Output = $p.StandardOutput.ReadToEnd()
        $p.WaitForExit()

        if (-not [string]::IsNullOrWhiteSpace($Output)) {
            $Json = $Output | ConvertFrom-Json

            # Default values if metric is missing
            $PowerHours    = "N/A"
            $PowerCycles   = "N/A"
            $UnsafeShutdowns = "N/A"

            # 1. Power On Hours (Handles NVMe and SATA JSON schemas)
            if ($Json.power_on_time.hours) {
                $PowerHours = $Json.power_on_time.hours
            } elseif ($Json.nvme_smart_health_information_log.power_on_hours) {
                $PowerHours = $Json.nvme_smart_health_information_log.power_on_hours
            }

            # 2. Power Cycles
            if ($Json.power_cycle_count) {
                $PowerCycles = $Json.power_cycle_count
            } elseif ($Json.nvme_smart_health_information_log.power_cycles) {
                $PowerCycles = $Json.nvme_smart_health_information_log.power_cycles
            }

            # 3. Unsafe Shutdowns (NVMe Health Log attribute 0xD)
            if ($null -ne $Json.nvme_smart_health_information_log.unsafe_shutdowns) {
                $UnsafeShutdowns = $Json.nvme_smart_health_information_log.unsafe_shutdowns
            } else {
                # SATA ATA Attribute Check (ID 192 / 0xC0 or ID 241)
                $Attr = $Json.ata_smart_attributes.table | Where-Object { $_.id -eq 192 -or $_.name -like "*Unsafe_Shutdown*" }
                if ($Attr) { $UnsafeShutdowns = $Attr.raw.value }
            }

            $Results += [PSCustomObject]@{
                "Disk Index"       = "Disk $DiskIndex"
                "Model"            = $Disk.FriendlyName
                "Power-On Hours"   = "$PowerHours hrs"
                "Power Cycles"     = $PowerCycles
                "Unsafe Shutdowns" = $UnsafeShutdowns
            }
        }
    } catch {}
}

# Output formatted table
$Results | Format-Table -AutoSize

Write-Host "==================================================" -ForegroundColor Cyan