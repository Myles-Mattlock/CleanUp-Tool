function Update-DriveHealthAndTemp {
    try {
        $PhysicalDisks = Get-PhysicalDisk -ErrorAction SilentlyContinue
        foreach ($Disk in $PhysicalDisks) {
            $TempStr = "N/A"
            $HealthStr = "Healthy"

            # 1. Try Direct NVMe Kernel Byte 05 Query First (Gets 98% on Samsung PM991a)
            $DirectHealth = [NVMeSmartReader]::GetNVMePercentageUsed($Disk.DeviceId)
            if ($DirectHealth -ge 0) {
                $HealthStr = "$DirectHealth% Health"
            } else {
                # 2. Fallback to Windows Operational / Health Status for USB / Enclosures
                if ($Disk.HealthStatus) { $HealthStr = $Disk.HealthStatus }
            }

            # Read Temperature via StorageReliabilityCounter
            try {
                $Counter = $Disk | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
                if ($Counter -and $Counter.Temperature -gt 0 -and $Counter.Temperature -lt 120) {
                    $TempStr = "$($Counter.Temperature) °C"
                }
            } catch {}

            # Map Physical Disk Number to Drive Letters
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
}Clear-Host
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "    USB ENCLOSURE SCSI PASS-THROUGH TEST" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

$Code = @"
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public class USBPassThrough {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern SafeFileHandle CreateFile(
        string lpFileName, uint dwDesiredAccess, uint dwShareMode,
        IntPtr lpSecurityAttributes, uint dwCreationDisposition,
        uint dwFlagsAndAttributes, IntPtr hTemplateFile);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool DeviceIoControl(
        SafeFileHandle hDevice, uint dwIoControlCode,
        IntPtr lpInBuffer, uint nInBufferSize,
        IntPtr lpOutBuffer, uint nOutBufferSize,
        ref uint lpBytesReturned, IntPtr lpOverlapped);

    [StructLayout(LayoutKind.Sequential)]
    public struct SCSI_PASS_THROUGH_DIRECT {
        public ushort Length;
        public byte ScsiStatus;
        public byte PathId;
        public byte TargetId;
        public byte Lun;
        public byte CdbLength;
        public byte SenseInfoLength;
        public byte DataIn;
        public uint DataTransferLength;
        public uint TimeOutValue;
        public IntPtr DataBuffer;
        public uint SenseInfoOffset;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 16)]
        public byte[] Cdb;
    }

    public static string ReadUSBTelemetry(int driveIndex) {
        string path = @"\\.\PhysicalDrive" + driveIndex;
        SafeFileHandle hDevice = CreateFile(path, 0x80000000 | 0x40000000, 1 | 2, IntPtr.Zero, 3, 0, IntPtr.Zero);
        if (hDevice.IsInvalid) {
            hDevice = CreateFile(path, 0, 1 | 2, IntPtr.Zero, 3, 0, IntPtr.Zero);
        }
        if (hDevice.IsInvalid) return "Access Denied / Handle Invalid";

        byte[] dataBuf = new byte[512];
        IntPtr pData = Marshal.AllocHGlobal(dataBuf.Length);

        // SCSI SAT (SCSI-ATA Translation) Pass-Through for ATA/NVMe SMART via USB
        SCSI_PASS_THROUGH_DIRECT sptd = new SCSI_PASS_THROUGH_DIRECT();
        sptd.Length = (ushort)Marshal.SizeOf(typeof(SCSI_PASS_THROUGH_DIRECT));
        sptd.CdbLength = 12;
        sptd.DataIn = 1; // SCSI_IOCTL_DATA_IN
        sptd.DataTransferLength = (uint)dataBuf.Length;
        sptd.TimeOutValue = 2;
        sptd.DataBuffer = pData;
        sptd.Cdb = new byte[16];

        // ATA READ SMART DATA command via SAT
        sptd.Cdb[0] = 0x85; // ATA PASS-THROUGH (16) / SAT
        sptd.Cdb[1] = (4 << 1) | 0; // PIO Data-In
        sptd.Cdb[2] = 0x2E; 
        sptd.Cdb[4] = 0xD0; // SMART Read Data command
        sptd.Cdb[6] = 0x01; // Sector count
        sptd.Cdb[8] = 0x4F; // LBA Mid (SMART Signature)
        sptd.Cdb[10] = 0xC2; // LBA High (SMART Signature)
        sptd.Cdb[14] = 0xB0; // ATA Command = SMART

        IntPtr pSptd = Marshal.AllocHGlobal(Marshal.SizeOf(sptd));
        Marshal.StructureToPtr(sptd, pSptd, false);

        uint bytesReturned = 0;
        // IOCTL_SCSI_PASS_THROUGH_DIRECT = 0x4D014
        bool success = DeviceIoControl(hDevice, 0x4D014, pSptd, (uint)Marshal.SizeOf(sptd), pSptd, (uint)Marshal.SizeOf(sptd), ref bytesReturned, IntPtr.Zero);

        string result = "PASS-THROUGH FAILED";
        if (success) {
            Marshal.Copy(pData, dataBuf, 0, dataBuf.Length);
            // Scan for temperature byte inside SAT SMART structure (Byte 194 or offset 115)
            byte temp = dataBuf[115];
            if (temp > 10 && temp < 100) {
                result = "SUCCESS -> Temp: " + temp + " °C";
            } else {
                result = "SCSI OK, but buffer structure offset needs adjustment.";
            }
        }

        Marshal.FreeHGlobal(pData);
        Marshal.FreeHGlobal(pSptd);
        hDevice.Close();
        return result;
    }
}
"@

Add-Type -TypeDefinition $Code -ErrorAction SilentlyContinue

0..1 | ForEach-Object {
    $DiskIndex = $_
    $DiskObj = Get-PhysicalDisk | Where-Object DeviceId -eq $DiskIndex -ErrorAction SilentlyContinue
    $Name = if ($DiskObj) { $DiskObj.FriendlyName } else { "PhysicalDrive$DiskIndex" }

    Write-Host "`nTesting SCSI Pass-Through on [$DiskIndex] $Name..." -ForegroundColor Yellow
    $Status = [USBPassThrough]::ReadUSBTelemetry($DiskIndex)
    Write-Host "  Result: $Status" -ForegroundColor Green
}

Write-Host "`n==================================================" -ForegroundColor Cyan