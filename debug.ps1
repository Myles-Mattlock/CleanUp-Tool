Clear-Host
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "    EXACT NVME PROTOCOL LOG PAGE TEST" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

$Code = @"
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public class NVMeDirect {
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
    public struct STORAGE_PROPERTY_QUERY {
        public uint PropertyId;
        public uint QueryType;
        public uint AdditionalParameters;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct STORAGE_PROTOCOL_SPECIFIC_DATA {
        public uint ProtocolType;
        public uint DataType;
        public uint ProtocolDataValue;
        public uint ProtocolDataSubValue;
        public uint ProtocolDataOffset;
        public uint ProtocolDataLength;
        public uint FixedProtocolReturnData;
        public uint Reserved;
    }

    public class NVMeResult {
        public int TempC = -1;
        public int HealthPercent = -1;
        public string StatusMsg = "";
    }

    public static NVMeResult ReadSmart(int driveIndex) {
        NVMeResult res = new NVMeResult();
        string path = @"\\.\PhysicalDrive" + driveIndex;

        SafeFileHandle hDevice = CreateFile(path, 0x80000000 | 0x40000000, 1 | 2, IntPtr.Zero, 3, 0, IntPtr.Zero);
        if (hDevice.IsInvalid) {
            hDevice = CreateFile(path, 0, 1 | 2, IntPtr.Zero, 3, 0, IntPtr.Zero);
        }

        if (hDevice.IsInvalid) {
            res.StatusMsg = "Access Denied / Handle Invalid (Win32 Error: " + Marshal.GetLastWin32Error() + ")";
            return res;
        }

        int querySize = Marshal.SizeOf(typeof(STORAGE_PROPERTY_QUERY)) + Marshal.SizeOf(typeof(STORAGE_PROTOCOL_SPECIFIC_DATA));
        byte[] buffer = new byte[querySize + 512];

        // STORAGE_PROPERTY_QUERY: PropertyId = 50 (StorageDeviceProtocolSpecificProperty), QueryType = 0
        BitConverter.GetBytes(50).CopyTo(buffer, 0);
        BitConverter.GetBytes(0).CopyTo(buffer, 4);

        // STORAGE_PROTOCOL_SPECIFIC_DATA: ProtocolType = 3 (NVMe), DataType = 2 (LogPage), Value = 2 (HealthInfo)
        int offset = Marshal.SizeOf(typeof(STORAGE_PROPERTY_QUERY));
        BitConverter.GetBytes(3).CopyTo(buffer, offset);       // ProtocolTypeNvme
        BitConverter.GetBytes(2).CopyTo(buffer, offset + 4);   // NVMeDataTypeLogPage
        BitConverter.GetBytes(2).CopyTo(buffer, offset + 8);   // NVME_LOG_PAGE_HEALTH_INFO
        BitConverter.GetBytes(0).CopyTo(buffer, offset + 12);  // SubValue
        BitConverter.GetBytes(40).CopyTo(buffer, offset + 16); // DataOffset
        BitConverter.GetBytes(512).CopyTo(buffer, offset + 20);// DataLength

        IntPtr pBuffer = Marshal.AllocHGlobal(buffer.Length);
        Marshal.Copy(buffer, 0, pBuffer, buffer.Length);

        uint bytesReturned = 0;
        bool success = DeviceIoControl(hDevice, 0x2D1400, pBuffer, (uint)buffer.Length, pBuffer, (uint)buffer.Length, ref bytesReturned, IntPtr.Zero);

        if (success) {
            byte[] outBytes = new byte[bytesReturned];
            Marshal.Copy(pBuffer, outBytes, 0, (int)bytesReturned);

            int dataOffset = 48;
            if (outBytes.Length >= dataOffset + 512) {
                ushort kelvin = BitConverter.ToUInt16(outBytes, dataOffset + 1);
                byte wear = outBytes[dataOffset + 5];

                if (kelvin > 200 && kelvin < 400) {
                    res.TempC = kelvin - 273;
                }
                if (wear <= 100) {
                    res.HealthPercent = 100 - wear;
                }
                res.StatusMsg = "OK";
            } else {
                res.StatusMsg = "Returned buffer too short (" + bytesReturned + " bytes)";
            }
        } else {
            res.StatusMsg = "DeviceIoControl failed (Error: " + Marshal.GetLastWin32Error() + ")";
        }

        Marshal.FreeHGlobal(pBuffer);
        hDevice.Close();
        return res;
    }
}
"@

Add-Type -TypeDefinition $Code -ErrorAction SilentlyContinue

0..1 | ForEach-Object {
    $DiskIndex = $_
    $DiskObj = Get-PhysicalDisk | Where-Object DeviceId -eq $DiskIndex -ErrorAction SilentlyContinue
    $Name = if ($DiskObj) { $DiskObj.FriendlyName } else { "PhysicalDrive$DiskIndex" }

    Write-Host "`nTesting NVMe Admin Log Page Query on [$DiskIndex] $Name..." -ForegroundColor Yellow
    $Result = [NVMeDirect]::ReadSmart($DiskIndex)

    if ($Result.TempC -gt 0) {
        Write-Host "  [SUCCESS] Temperature: $($Result.TempC) °C" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] Temperature: N/A ($($Result.StatusMsg))" -ForegroundColor Red
    }

    if ($Result.HealthPercent -ge 0) {
        Write-Host "  [SUCCESS] Health:      $($Result.HealthPercent)% Health" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] Health:         N/A ($($Result.StatusMsg))" -ForegroundColor Red
    }
}

Write-Host "`n==================================================" -ForegroundColor Cyan