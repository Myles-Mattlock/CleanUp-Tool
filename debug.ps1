Clear-Host
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "    USB ENCLOSURE NVME PAYLOAD DECODER" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

$Code = @"
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public class USBTelemetryReader {
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

    public class TelemetryResult {
        public int TempC = -1;
        public int HealthPercent = -1;
        public string Status = "";
    }

    public static TelemetryResult GetUSBStats(int driveIndex) {
        TelemetryResult res = new TelemetryResult();
        string path = @"\\.\PhysicalDrive" + driveIndex;
        SafeFileHandle hDevice = CreateFile(path, 0x80000000 | 0x40000000, 1 | 2, IntPtr.Zero, 3, 0, IntPtr.Zero);
        if (hDevice.IsInvalid) {
            hDevice = CreateFile(path, 0, 1 | 2, IntPtr.Zero, 3, 0, IntPtr.Zero);
        }
        if (hDevice.IsInvalid) {
            res.Status = "Access Denied";
            return res;
        }

        byte[] dataBuf = new byte[512];
        IntPtr pData = Marshal.AllocHGlobal(dataBuf.Length);

        SCSI_PASS_THROUGH_DIRECT sptd = new SCSI_PASS_THROUGH_DIRECT();
        sptd.Length = (ushort)Marshal.SizeOf(typeof(SCSI_PASS_THROUGH_DIRECT));
        sptd.CdbLength = 12;
        sptd.DataIn = 1;
        sptd.DataTransferLength = (uint)dataBuf.Length;
        sptd.TimeOutValue = 2;
        sptd.DataBuffer = pData;
        sptd.Cdb = new byte[16];

        // SCSI SAT ATA Pass-Through (16)
        sptd.Cdb[0] = 0x85; 
        sptd.Cdb[1] = (4 << 1) | 0; 
        sptd.Cdb[2] = 0x2E; 
        sptd.Cdb[4] = 0xD0; 
        sptd.Cdb[6] = 0x01; 
        sptd.Cdb[8] = 0x4F; 
        sptd.Cdb[10] = 0xC2; 
        sptd.Cdb[14] = 0xB0; 

        IntPtr pSptd = Marshal.AllocHGlobal(Marshal.SizeOf(sptd));
        Marshal.StructureToPtr(sptd, pSptd, false);

        uint bytesReturned = 0;
        bool success = DeviceIoControl(hDevice, 0x4D014, pSptd, (uint)Marshal.SizeOf(sptd), pSptd, (uint)Marshal.SizeOf(sptd), ref bytesReturned, IntPtr.Zero);

        if (success) {
            Marshal.Copy(pData, dataBuf, 0, dataBuf.Length);

            // 1. Check for Kelvin Temp at Offset 1-2
            ushort kelvin = (ushort)(dataBuf[1] | (dataBuf[2] << 8));
            if (kelvin >= 273 && kelvin <= 373) {
                res.TempC = kelvin - 273;
            } else {
                // Fallback scan for raw Celsius byte
                for (int i = 0; i < 500; i++) {
                    if (dataBuf[i] >= 20 && dataBuf[i] <= 85 && dataBuf[i+1] == 0) {
                        res.TempC = dataBuf[i];
                        break;
                    }
                }
            }

            // 2. Read NVMe Wear Percentage at Offset 5
            byte wear = dataBuf[5];
            if (wear <= 100) {
                res.HealthPercent = 100 - wear;
            }

            res.Status = "OK";
        } else {
            res.Status = "SCSI IOCTL Failed";
        }

        Marshal.FreeHGlobal(pData);
        Marshal.FreeHGlobal(pSptd);
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

    Write-Host "`nDecoding NVMe Payload on [$DiskIndex] $Name..." -ForegroundColor Yellow
    $Res = [USBTelemetryReader]::GetUSBStats($DiskIndex)

    if ($Res.TempC -gt 0) {
        Write-Host "  [SUCCESS] Temperature: $($Res.TempC) °C" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] Temperature: N/A ($($Res.Status))" -ForegroundColor Red
    }

    if ($Res.HealthPercent -ge 0) {
        Write-Host "  [SUCCESS] Health:      $($Res.HealthPercent)% Health" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] Health:         N/A ($($Res.Status))" -ForegroundColor Red
    }
}

Write-Host "`n==================================================" -ForegroundColor Cyan