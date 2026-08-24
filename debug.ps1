function Get-SmartctlData ($DiskIndex) {
    $SmartctlPath = Join-Path $CurrentDir "smartctl.exe"
    
    # Fallback to system PATH if not in the local script folder
    if (-not (Test-Path $SmartctlPath)) {
        $SmartctlPath = "smartctl.exe"
    }

    try {
        # Query physical drive using JSON output
        $ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo -Property @{
            FileName               = $SmartctlPath
            Arguments              = "-j -a /dev/pd$DiskIndex"
            UseShellExecute        = $false
            RedirectStandardOutput = $true
            CreateNoWindow         = $true
        }
        $p = [System.Diagnostics.Process]::Start($ProcessInfo)
        $Output = $p.StandardOutput.ReadToEnd()
        $p.WaitForExit()

        if (-not [string]::IsNullOrWhiteSpace($Output)) {
            return ($Output | ConvertFrom-Json)
        }
    } catch {}
    return $null
}

function Update-DriveHealthAndTemp {
    try {
        $PhysicalDisks = Get-PhysicalDisk -ErrorAction SilentlyContinue
        foreach ($Disk in $PhysicalDisks) {
            $TempStr = "N/A"
            $HealthStr = "Healthy"

            # 1. Query smartctl JSON
            $Json = Get-SmartctlData -DiskIndex $Disk.DeviceId

            if ($Json) {
                # Read Temperature (Handles both NVMe & SATA JSON schemas)
                if ($Json.temperature.current) {
                    $TempStr = "$($Json.temperature.current) °C"
                } elseif ($Json.nvme_smart_health_information_log.temperature) {
                    $TempStr = "$($Json.nvme_smart_health_information_log.temperature) °C"
                }

                # Read Health / Wear Percentage
                if ($null -ne $Json.nvme_smart_health_information_log.percentage_used) {
                    # NVMe percentage used (100 - used)
                    $Used = [int]$Json.nvme_smart_health_information_log.percentage_used
                    $HealthStr = "$(100 - $Used)% Health"
                } elseif ($Json.smart_status.passed -eq $true) {
                    $HealthStr = "100% Health"
                }
            } else {
                # Fallback to Windows WMI status if smartctl is missing or fails
                if ($Disk.HealthStatus) { $HealthStr = $Disk.HealthStatus }
            }

            # 2. Map Physical Disk Number to Volume Drive Letters
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