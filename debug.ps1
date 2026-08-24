Clear-Host
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "    DIRECT NVME KERNEL TELEMETRY TEST" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

$Code = @"
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public class NVMeReader {
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

    public class DriveStats {
        public int TemperatureC = -1;
        public int HealthPercent = -1;
        public string Error = "";
    }

    public static DriveStats GetNVMeStats(int driveIndex) {
        DriveStats stats = new DriveStats();
        string path = @"\\.\PhysicalDrive" + driveIndex;
        
        SafeFileHandle hDevice = CreateFile(path, 0x80000000 | 0x40000000, 1 | 2, IntPtr.Zero, 3, 0, IntPtr.Zero);
        if (hDevice.IsInvalid) {
            hDevice = CreateFile(path, 0, 1 | 2, IntPtr.Zero, 3, 0, IntPtr.Zero);
        }
        
        if (hDevice.IsInvalid) {
            stats.Error = "Access Denied / Driver Lock";
            return stats;
        }

        // IOCTL_STORAGE_QUERY_PROPERTY = 0x2D1400
        byte[] inBuffer = new byte[12];
        BitConverter.GetBytes(0x06).CopyTo(inBuffer, 0); // PropertyId = StorageDeviceProtocolSpecificProperty
        BitConverter.GetBytes(0x00).CopyTo(inBuffer, 4); // QueryType = PropertyStandardQuery
        BitConverter.GetBytes(0x02).CopyTo(inBuffer, 8); // ProtocolType = ProtocolTypeNvme

        byte[] outBuffer = new byte[4096];
        uint bytesReturned = 0;

        IntPtr pIn = Marshal.AllocHGlobal(inBuffer.Length);
        IntPtr pOut = Marshal.AllocHGlobal(outBuffer.Length);

        Marshal.Copy(inBuffer, 0, pIn, inBuffer.Length);

        bool success = DeviceIoControl(hDevice, 0x2D1400, pIn, (uint)inBuffer.Length, pOut, (uint)outBuffer.Length, ref bytesReturned, IntPtr.Zero);

        if (success && bytesReturned > 0) {
            Marshal.Copy(pOut, outBuffer, 0, (int)bytesReturned);
            
            // SMART Data payload offset check
            for (int i = 0; i < (int)bytesReturned - 512; i++) {
                // Read Kelvin Temperature at offset
                ushort kelvin = BitConverter.ToUInt16(outBuffer, i + 1);
                byte wear = outBuffer[i + 5];

                if (kelvin >= 273 && kelvin <= 373 && wear <= 100) {
                    stats.TemperatureC = kelvin - 273;
                    stats.HealthPercent = 100 - wear;
                    break;
                }
            }
        } else {
            stats.Error = "IOCTL Failed (Error Code " + Marshal.GetLastWin32Error() + ")";
        }

        Marshal.FreeHGlobal(pIn);
        Marshal.FreeHGlobal(pOut);
        hDevice.Close();

        return stats;
    }
}
"@

Add-Type -TypeDefinition $Code -ErrorAction SilentlyContinue

0..1 | ForEach-Object {
    $DiskIndex = $_
    Write-Host "`nTesting NVMe Kernel Query on PhysicalDrive$DiskIndex..." -ForegroundColor Yellow
    
    $Stats = [NVMeReader]::GetNVMeStats($DiskIndex)
    
    if ($Stats.TemperatureC -gt 0) {
        Write-Host "  [SUCCESS] Temperature: $($Stats.TemperatureC) °C" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] Temperature: Could not read ($($Stats.Error))" -ForegroundColor Red
    }

    if ($Stats.HealthPercent -ge 0) {
        Write-Host "  [SUCCESS] Health:      $($Stats.HealthPercent)% Health" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] Health:         Could not read ($($Stats.Error))" -ForegroundColor Red
    }
}

Write-Host "`n==================================================" -ForegroundColor Cyan