Clear-Host
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "    DIRECT NVME SMART BYTE 05 TELEMETRY READ" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

$Code = @"
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public class NVMeSmartReader {
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

    public static int GetNVMePercentageUsed(int diskIndex) {
        string path = @"\\.\PhysicalDrive" + diskIndex;
        SafeFileHandle hDevice = CreateFile(path, 0x80000000 | 0x40000000, 1 | 2, IntPtr.Zero, 3, 0, IntPtr.Zero);
        if (hDevice.IsInvalid) {
            hDevice = CreateFile(path, 0, 1 | 2, IntPtr.Zero, 3, 0, IntPtr.Zero);
        }
        if (hDevice.IsInvalid) return -1;

        // Query Protocol Property Buffer for NVMe Log Page 0x02
        byte[] buffer = new byte[4096];
        BitConverter.GetBytes(50).CopyTo(buffer, 0); // PropertyId = StorageDeviceProtocolSpecificProperty
        BitConverter.GetBytes(0).CopyTo(buffer, 4);  // QueryType = PropertyStandardQuery
        BitConverter.GetBytes(3).CopyTo(buffer, 8);  // ProtocolType = ProtocolTypeNvme
        BitConverter.GetBytes(2).CopyTo(buffer, 12); // DataType = NVMeDataTypeLogPage
        BitConverter.GetBytes(2).CopyTo(buffer, 16); // ProtocolDataValue = HealthInfo
        BitConverter.GetBytes(40).CopyTo(buffer, 24); // DataOffset
        BitConverter.GetBytes(512).CopyTo(buffer, 28); // DataLength

        IntPtr pBuf = Marshal.AllocHGlobal(buffer.Length);
        Marshal.Copy(buffer, 0, pBuf, buffer.Length);

        uint bytesReturned = 0;
        bool success = DeviceIoControl(hDevice, 0x2D1400, pBuf, (uint)buffer.Length, pBuf, (uint)buffer.Length, ref bytesReturned, IntPtr.Zero);

        int healthPercent = -1;
        if (success && bytesReturned >= 512) {
            byte[] outData = new byte[bytesReturned];
            Marshal.Copy(pBuf, outData, 0, (int)bytesReturned);

            // Byte 5 in NVMe SMART Health Info Log is "Percentage Used"
            for (int i = 0; i < outData.Length - 512; i++) {
                byte percentageUsed = outData[i + 48 + 5];
                if (percentageUsed <= 100) {
                    healthPercent = 100 - percentageUsed;
                    break;
                }
            }
        }

        Marshal.FreeHGlobal(pBuf);
        hDevice.Close();
        return healthPercent;
    }
}
"@

Add-Type -TypeDefinition $Code -ErrorAction SilentlyContinue

0..1 | ForEach-Object {
    $Index = $_
    $DiskObj = Get-PhysicalDisk | Where-Object DeviceId -eq $Index -ErrorAction SilentlyContinue
    $Name = if ($DiskObj) { $DiskObj.FriendlyName } else { "Disk $Index" }
    
    $Health = [NVMeSmartReader]::GetNVMePercentageUsed($Index)
    if ($Health -ge 0) {
        Write-Host "Physical Disk [$Index] ($Name): $Health% Health" -ForegroundColor Green
    } else {
        Write-Host "Physical Disk [$Index] ($Name): Unable to read raw NVMe byte 05" -ForegroundColor Yellow
    }
}

Write-Host "==================================================" -ForegroundColor Cyan