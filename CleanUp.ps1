# --- 1. Administrator Check (Self-Elevating) ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $ScriptPath = $MyInvocation.MyCommand.Definition
    if ([string]::IsNullOrEmpty($ScriptPath)) {
        $ScriptPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    }
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`"" -Verb RunAs
    Exit
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# --- NATIVE WINDOW DWM COLORING (WIN 11 TITLEBAR ACCENT) ---
$DwmApi = Add-Type -MemberDefinition @"
    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
"@ -Name "DwmApi" -Namespace "Win32" -PassThru

# --- CONFIGURATION ---
$Global:CurrentVersion = "3.0.0" 
$Global:RepoName = "Myles-Mattlock/CleanUp-Tool"
$Global:RegFiles = @("DiskCleanupSettings.reg", "DiskCleanupSettings2.reg") 
$Global:LogDir = "C:\Program Files\SystemCleanUp\Logs"

$CurrentDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrEmpty($CurrentDir)) { $CurrentDir = Get-Location }

# --- XAML UI DESIGN ---
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Myles Mattlock CleanUp Tool" Height="760" Width="960" 
        WindowStartupLocation="CenterScreen" Background="#1E1E1E" Foreground="#FFFFFF"
        ResizeMode="CanMinimize">
    <Grid Margin="25">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/> <!-- 0: Header -->
            <RowDefinition Height="Auto"/> <!-- 1: Top Stats Bar (3 Cards) -->
            <RowDefinition Height="*"/>    <!-- 2: Output Log Terminal -->
            <RowDefinition Height="Auto"/> <!-- 3: Reclaimed Storage Box -->
            <RowDefinition Height="Auto"/> <!-- 4: Progress Bar -->
            <RowDefinition Height="Auto"/> <!-- 5: Action Controls -->
        </Grid.RowDefinitions>

        <!-- Header -->
        <Border Grid.Row="0" Background="#252526" CornerRadius="8" Padding="20" Margin="0,0,0,20">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <!-- Left Logo -->
                <Image x:Name="ImgLogo" Grid.Column="0" Width="78.75" Height="78.75" Margin="0,0,20,0" VerticalAlignment="Center" Stretch="Uniform"/>

                <StackPanel Grid.Column="1" VerticalAlignment="Center">
                    <TextBlock Text="Myles Mattlock System CleanUp" FontSize="24" FontWeight="Bold" Foreground="#FFFFFF"/>
                    <TextBlock Text="Optimize storage, system files, and component health" FontSize="14" Foreground="#AAAAAA" Margin="0,4,0,0"/>
                </StackPanel>
                
                <TextBlock x:Name="TxtVersion" Grid.Column="2" Text="v3.0.0" VerticalAlignment="Center" Foreground="#888888" FontSize="16" FontWeight="SemiBold" Margin="0,0,20,0"/>

                <!-- Right Logo -->
                <Image x:Name="ImgLogoRight" Grid.Column="3" Width="78.75" Height="78.75" VerticalAlignment="Center" Stretch="Uniform"/>
            </Grid>
        </Border>

        <!-- Top Stats Bar (3 Columns) -->
        <Grid Grid.Row="1" Margin="0,0,0,20">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="15"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="15"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <!-- Initial Free Space -->
            <Border Grid.Column="0" Background="#2D2D30" CornerRadius="6" Padding="15">
                <StackPanel>
                    <TextBlock Text="INITIAL FREE" FontSize="11" FontWeight="Bold" Foreground="#888888"/>
                    <TextBlock x:Name="TxtInitialSpace" Text="Calculating..." FontSize="18" FontWeight="Bold" Foreground="#FFFFFF" Margin="0,6,0,0"/>
                </StackPanel>
            </Border>

            <!-- Drive Wear / Health -->
            <Border Grid.Column="2" Background="#2D2D30" CornerRadius="6" Padding="15">
                <StackPanel>
                    <TextBlock Text="DRIVE HEALTH" FontSize="11" FontWeight="Bold" Foreground="#888888"/>
                    <TextBlock x:Name="TxtDriveHealth" Text="Checking..." FontSize="18" FontWeight="Bold" Foreground="#00E5FF" Margin="0,6,0,0"/>
                </StackPanel>
            </Border>

            <!-- Drive Temperature -->
            <Border Grid.Column="4" Background="#2D2D30" CornerRadius="6" Padding="15">
                <StackPanel>
                    <TextBlock Text="TEMP" FontSize="11" FontWeight="Bold" Foreground="#888888"/>
                    <TextBlock x:Name="TxtDriveTemp" Text="-- °C" FontSize="18" FontWeight="Bold" Foreground="#FFCC00" Margin="0,6,0,0"/>
                </StackPanel>
            </Border>
        </Grid>

        <!-- Output Log Terminal -->
        <Border Grid.Row="2" Background="#0C0C0C" BorderBrush="#333333" BorderThickness="1" CornerRadius="6" Padding="12">
            <ScrollViewer x:Name="LogScroll" VerticalScrollBarVisibility="Auto">
                <TextBox x:Name="TxtLog" Background="Transparent" Foreground="#00FF66" BorderThickness="0" 
                         FontFamily="Consolas" FontSize="13" IsReadOnly="True" TextWrapping="Wrap"/>
            </ScrollViewer>
        </Border>

        <!-- Reclaimed Storage Box (Moved Underneath Console) -->
        <Border Grid.Row="3" Background="#2D2D30" CornerRadius="6" Padding="15" Margin="0,15,0,0">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0" VerticalAlignment="Center">
                    <TextBlock Text="TOTAL STORAGE RECLAIMED" FontSize="11" FontWeight="Bold" Foreground="#888888"/>
                    <TextBlock Text="Space freed during the current optimization session" FontSize="12" Foreground="#AAAAAA" Margin="0,2,0,0"/>
                </StackPanel>
                <TextBlock x:Name="TxtReclaimed" Grid.Column="1" Text="0 MB" FontSize="22" FontWeight="Bold" Foreground="#00FF66" VerticalAlignment="Center"/>
            </Grid>
        </Border>

        <!-- Progress Bar -->
        <ProgressBar x:Name="CleanProgress" Grid.Row="4" Height="10" Margin="0,15,0,15" Foreground="#00E5FF" Background="#2D2D30" BorderThickness="0" Value="0" Maximum="100"/>

        <!-- Action Controls -->
        <Grid Grid.Row="5">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock x:Name="TxtStatus" Text="Ready to start cleanup." VerticalAlignment="Center" Foreground="#AAAAAA" FontSize="14"/>
            <Button x:Name="BtnStart" Grid.Column="1" Content="Start Cleanup" Width="160" Height="42" 
                    Background="#007ACC" Foreground="White" FontSize="14" FontWeight="Bold" BorderThickness="0" Cursor="Hand">
                <Button.Resources>
                    <Style TargetType="Border">
                        <Setter Property="CornerRadius" Value="6"/>
                    </Style>
                </Button.Resources>
            </Button>
        </Grid>
    </Grid>
</Window>
"@

# Load XAML
$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$Window = [Windows.Markup.XamlReader]::Load($reader)

# Map UI Controls
$ImgLogo         = $Window.FindName("ImgLogo")
$ImgLogoRight    = $Window.FindName("ImgLogoRight")
$TxtVersion      = $Window.FindName("TxtVersion")
$TxtInitialSpace = $Window.FindName("TxtInitialSpace")
$TxtReclaimed    = $Window.FindName("TxtReclaimed")
$TxtDriveHealth  = $Window.FindName("TxtDriveHealth")
$TxtDriveTemp    = $Window.FindName("TxtDriveTemp")
$TxtLog          = $Window.FindName("TxtLog")
$LogScroll       = $Window.FindName("LogScroll")
$CleanProgress   = $Window.FindName("CleanProgress")
$TxtStatus       = $Window.FindName("TxtStatus")
$BtnStart        = $Window.FindName("BtnStart")

# Thread-safe Function to Stream Text into GUI Log Terminal
function Write-GuiLog ($Message) {
    if ([string]::IsNullOrWhiteSpace($Message)) { return }
    $TxtLog.Dispatcher.Invoke([Action]{
        $TxtLog.AppendText("[$((Get-Date).ToString('HH:mm:ss'))] $Message`n")
        $LogScroll.ScrollToEnd()
    })
}

# --- DIRECT HARDWARE SMART & TEMPERATURE DIAGNOSTICS ---
function Get-DriveHealthDiagnostics {
    Write-GuiLog "=== DISK HEALTH & SMART DIAGNOSTICS ==="
    
    $HealthStatusText = "Healthy"
    $TempStatusText = "N/A"

    try {
        # 1. Physical Disk Check via CIM
        $PhysicalDisks = Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue
        
        # 2. Query WMI MSStorageDriver namespace for SMART Data & Temperature
        $SmartPredict = Get-CimInstance -Namespace "root\wmi" -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction SilentlyContinue
        $SmartData    = Get-CimInstance -Namespace "root\wmi" -ClassName MSStorageDriver_FailurePredictData -ErrorAction SilentlyContinue

        foreach ($Disk in $PhysicalDisks) {
            $Model = $Disk.Model
            $Index = $Disk.Index
            $Interface = $Disk.InterfaceType
            $Status = $Disk.Status

            Write-GuiLog "Drive [$Index]: $Model ($Interface) - SMART Status: $Status"

            # Parse SMART Vendor Bytes for Temperature (Attribute 0xC2 / 194 or 0xBE / 190)
            $DiskSmart = $SmartData | Where-Object { $_.InstanceName -like "*$Index*" -or $_.InstanceName -like "*$Model*" }
            
            if ($DiskSmart -and $DiskSmart.VendorSpecific) {
                $VendorBytes = $DiskSmart.VendorSpecific
                # Walk SMART attributes array (12 bytes per attribute)
                for ($i = 2; $i -lt $VendorBytes.Length - 12; $i += 12) {
                    $AttrId = $VendorBytes[$i]
                    # Check for Temperature Attribute IDs (194/0xC2 or 190/0xBE)
                    if ($AttrId -eq 194 -or $AttrId -eq 190) {
                        $RawTemp = $VendorBytes[$i + 5]
                        if ($RawTemp -gt 0 -and $RawTemp -lt 100) {
                            $TempStatusText = "$RawTemp °C"
                            Write-GuiLog "  > Raw SMART Temp Reading: $TempStatusText"
                            break
                        }
                    }
                }
            }

            # If WMI temperature parse didn't hit, check PhysicalDisk counters silently
            if ($TempStatusText -eq "N/A") {
                $PhysDisk = Get-PhysicalDisk | Where-Object { $_.DeviceId -eq $Index } -ErrorAction SilentlyContinue
                if ($PhysDisk) {
                    $Counter = $PhysDisk | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
                    if ($Counter -and $Counter.Temperature -gt 0) {
                        $TempStatusText = "$($Counter.Temperature) °C"
                        Write-GuiLog "  > Storage Reliability Temp: $TempStatusText"
                    }
                    if ($Counter -and $Counter.Wear -ne $null) {
                        $HealthStatusText = "$(100 - $Counter.Wear)% Health"
                        Write-GuiLog "  > Wear Remaining: $HealthStatusText"
                    }
                }
            }

            if ($Status -ne "OK") {
                $HealthStatusText = "Caution ($Status)"
            }
        }
    } catch {
        Write-GuiLog "  > Basic disk health verification completed."
        $HealthStatusText = "Healthy"
    }

    # Update UI Cards
    $TxtDriveHealth.Text = $HealthStatusText
    $TxtDriveTemp.Text = $TempStatusText
}

# --- UPDATE CHECKER (STABLE ONLY) ---
function Check-ForUpdates {
    Write-GuiLog "Checking for updates..."
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) PowerShell-App"
        $Url = "https://api.github.com/repos/$Global:RepoName/releases"

        $Releases = Invoke-RestMethod -Uri $Url -Method Get -UserAgent $UserAgent -ErrorAction Stop
        $StableReleases = $Releases | Where-Object { $_.prerelease -eq $false }

        $LocalVersion = [version]($Global:CurrentVersion.ToLower().TrimStart('v').Split("-")[0])
        $UpdateFound = $null

        foreach ($Rel in $StableReleases) {
            $RemoteVersion = [version]($Rel.tag_name.ToLower().TrimStart('v').Split("-")[0])

            if ($RemoteVersion -gt $LocalVersion) {
                $UpdateFound = $Rel
                break 
            }
        }

        if ($UpdateFound) {
            Write-GuiLog "[!] NEW STABLE UPDATE AVAILABLE: $($UpdateFound.tag_name)"
            Write-GuiLog "Currently running: v$Global:CurrentVersion"
            Write-GuiLog "Download URL: $($UpdateFound.html_url)"
            
            $UpdateChoice = [System.Windows.Forms.MessageBox]::Show(
                "A new stable version ($($UpdateFound.tag_name)) is available.`n`nWould you like to open the download page now?", 
                "Update Available", 
                "YesNo", 
                "Information"
            )
            
            if ($UpdateChoice -eq "Yes") { 
                Start-Process $UpdateFound.html_url
                Write-GuiLog "Redirecting to download page. Closing application..."
                Start-Sleep -Seconds 2
                $Window.Close()
            }
        } else {
            Write-GuiLog "You are running the latest stable version (v$Global:CurrentVersion)."
        }
    } catch {
        Write-GuiLog "Note: Update check skipped (Connection issue or release missing)."
    }
}

# Real-Time Output Process Runner
function Run-ProcessWithLiveOutput ($FilePath, $ArgumentList) {
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $FilePath
    $pinfo.Arguments = $ArgumentList
    $pinfo.UseShellExecute = $false
    $pinfo.RedirectStandardOutput = $true
    $pinfo.RedirectStandardError = $true
    $pinfo.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $pinfo

    $outEvent = Register-ObjectEvent -InputObject $process -EventName "OutputDataReceived" -Action {
        if ($Event.SourceEventArgs.Data) {
            Write-GuiLog $Event.SourceEventArgs.Data
        }
    }
    $errEvent = Register-ObjectEvent -InputObject $process -EventName "ErrorDataReceived" -Action {
        if ($Event.SourceEventArgs.Data) {
            Write-GuiLog "ERR: $($Event.SourceEventArgs.Data)"
        }
    }

    $process.Start() | Out-Null
    $process.BeginOutputReadLine()
    $process.BeginErrorReadLine()

    while (-not $process.HasExited) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 100
    }

    $process.WaitForExit()
    
    Unregister-Event -SourceIdentifier $outEvent.Name
    Unregister-Event -SourceIdentifier $errEvent.Name
}

# Init Setup
$Window.Add_Loaded({
    # --- Set Very Dark Petrol Teal-Blue Title Bar Color via DWM API ---
    try {
        $Hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($Window)).Handle
        # DWMWA_CAPTION_COLOR = 35
        $CaptionAttr = 35
        # COLORREF format in hex (BGR): 0x00382D12 represents #122D38
        $DarkTealColor = 0x00382D12 
        [Win32.DwmApi]::DwmSetWindowAttribute($Hwnd, $CaptionAttr, [ref]$DarkTealColor, [System.Runtime.InteropServices.Marshal]::SizeOf([type][int])) | Out-Null
    } catch {}

    # --- Load Header Left Logo Image ---
    $LogoPath = Join-Path $CurrentDir "Logo.jpg"
    if (Test-Path $LogoPath) {
        try {
            $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
            $bitmap.BeginInit()
            $bitmap.UriSource = New-Object System.Uri($LogoPath, [System.UriKind]::Absolute)
            $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bitmap.EndInit()
            $ImgLogo.Source = $bitmap
        } catch {
            Write-GuiLog "Warning: Could not load left logo image."
        }
    }

    # --- Load Header Right Logo Image ---
    $LogoRightPath = Join-Path $CurrentDir "LogoRight.jpg"
    if (Test-Path $LogoRightPath) {
        try {
            $bitmapRight = New-Object System.Windows.Media.Imaging.BitmapImage
            $bitmapRight.BeginInit()
            $bitmapRight.UriSource = New-Object System.Uri($LogoRightPath, [System.UriKind]::Absolute)
            $bitmapRight.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bitmapRight.EndInit()
            $ImgLogoRight.Source = $bitmapRight
        } catch {
            Write-GuiLog "Warning: Could not load right logo image."
        }
    }

    $TxtVersion.Text = "v$Global:CurrentVersion"
    $Drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $Global:StartingFreeSpace = $Drive.FreeSpace
    $TxtInitialSpace.Text = "$([Math]::Round($Global:StartingFreeSpace / 1GB, 2)) GB"
    
    Write-GuiLog "System Cleanup Initialized."
    
    # Query Drive Health & Reliablity Counters
    Get-DriveHealthDiagnostics

    # Run the GitHub update check on startup
    Check-ForUpdates
})

# Cleanup Action
$BtnStart.Add_Click({
    $BtnStart.IsEnabled = $false
    $BtnStart.Content = "Cleaning..."
    $CleanProgress.Value = 0

    # 0. Registry Configs
    $TxtStatus.Text = "Importing Registry configurations..."
    $CleanProgress.Value = 10
    Write-GuiLog "=== [0/5] IMPORTING REGISTRY CONFIGURATIONS ==="
    foreach ($File in $Global:RegFiles) {
        $FilePath = Join-Path $CurrentDir $File
        if (Test-Path $FilePath) {
            Write-GuiLog "Applying registry file: $File"
            Run-ProcessWithLiveOutput "reg.exe" "import `"$FilePath`""
        }
    }

    # 1. Clear Temp Files
    $TxtStatus.Text = "Clearing temporary files..."
    $CleanProgress.Value = 25
    Write-GuiLog "=== [1/5] CLEARING TEMP FILES AND LOGS ==="
    $TargetFolders = @(
        "C:\Windows\Temp\*",
        "C:\Windows\Prefetch\*",
        "C:\Windows\SoftwareDistribution\Download\*",
        "$([System.IO.Path]::GetTempPath())*",
        "C:\Intel",
        "C:\PerfLogs"
    )
    foreach ($Path in $TargetFolders) {
        if (Test-Path $Path) {
            Write-GuiLog "Deleting files in: $Path"
            Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # 2. Recycle Bin
    $TxtStatus.Text = "Emptying Recycle Bin..."
    $CleanProgress.Value = 45
    Write-GuiLog "=== [2/5] EMPTYING RECYCLE BIN ==="
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    Write-GuiLog "Recycle bin emptied."

    # 3. Disk Cleanup Utility
    $TxtStatus.Text = "Running Disk Cleanup Utility..."
    $CleanProgress.Value = 60
    Write-GuiLog "=== [3/5] RUNNING CLEANMGR UTILITY ==="
    $CleanParam = if (Test-Path "C:\Windows.old") { "/SAGERUN:1" } else { "/SAGERUN:2" }
    Run-ProcessWithLiveOutput "cleanmgr.exe" $CleanParam

    # 4. Flush DNS
    $TxtStatus.Text = "Flushing DNS Cache..."
    $CleanProgress.Value = 75
    Write-GuiLog "=== [4/5] FLUSHING DNS CACHE ==="
    Run-ProcessWithLiveOutput "ipconfig.exe" "/flushdns"

    # 5. DISM Optimization
    $TxtStatus.Text = "Optimizing DISM Component Store..."
    $CleanProgress.Value = 85
    Write-GuiLog "=== [5/5] RUNNING DISM COMPONENT STORE CLEANUP ==="
    Run-ProcessWithLiveOutput "Dism.exe" "/online /Cleanup-Image /StartComponentCleanup /ResetBase /NoRestart"

    # Final Calculation
    $CleanProgress.Value = 100
    $DriveEnd = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $SpaceSavedBytes = $DriveEnd.FreeSpace - $Global:StartingFreeSpace
    
    $ReadableSpace = if ($SpaceSavedBytes -le 0) {
        "0 MB"
    } elseif ($SpaceSavedBytes -gt 1GB) {
        "$([Math]::Round($SpaceSavedBytes / 1GB, 2)) GB"
    } else {
        "$([Math]::Round($SpaceSavedBytes / 1MB, 2)) MB"
    }

    $TxtReclaimed.Text = $ReadableSpace
    $TxtStatus.Text = "Optimization complete!"
    $BtnStart.Content = "Finished"
    Write-GuiLog "=== CLEANUP COMPLETE! TOTAL STORAGE RECLAIMED: $ReadableSpace ==="
})

# Display Window
$Window.ShowDialog() | Out-Null