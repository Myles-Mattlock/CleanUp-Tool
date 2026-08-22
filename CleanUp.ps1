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
        Title="Myles Mattlock CleanUp Tool" Height="820" Width="960" 
        WindowStartupLocation="CenterScreen" Background="#1E1E1E" Foreground="#FFFFFF"
        ResizeMode="CanMinimize">
    <Grid Margin="25">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/> <!-- 0: Header -->
            <RowDefinition Height="Auto"/> <!-- 1: Top Stats Bar -->
            <RowDefinition Height="Auto"/> <!-- 2: Task Checkboxes & Profile Buttons -->
            <RowDefinition Height="*"/>    <!-- 3: Output Log Terminal -->
            <RowDefinition Height="Auto"/> <!-- 4: Reclaimed Storage Box -->
            <RowDefinition Height="Auto"/> <!-- 5: Progress Bar -->
            <RowDefinition Height="Auto"/> <!-- 6: Action Controls -->
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

                <Image x:Name="ImgLogo" Grid.Column="0" Width="78.75" Height="78.75" Margin="0,0,20,0" VerticalAlignment="Center" Stretch="Uniform"/>

                <StackPanel Grid.Column="1" VerticalAlignment="Center">
                    <TextBlock Text="Myles Mattlock System CleanUp" FontSize="24" FontWeight="Bold" Foreground="#FFFFFF"/>
                    <TextBlock Text="Optimize storage, system files, and component health" FontSize="14" Foreground="#AAAAAA" Margin="0,4,0,0"/>
                </StackPanel>
                
                <TextBlock x:Name="TxtVersion" Grid.Column="2" Text="v3.0.0" VerticalAlignment="Center" Foreground="#888888" FontSize="16" FontWeight="SemiBold" Margin="0,0,20,0"/>

                <Image x:Name="ImgLogoRight" Grid.Column="3" Width="78.75" Height="78.75" VerticalAlignment="Center" Stretch="Uniform"/>
            </Grid>
        </Border>

        <!-- Top Stats Bar -->
        <Grid Grid.Row="1" Margin="0,0,0,15">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="15"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="15"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <Border Grid.Column="0" Background="#2D2D30" CornerRadius="6" Padding="15">
                <StackPanel>
                    <TextBlock Text="INITIAL FREE" FontSize="11" FontWeight="Bold" Foreground="#888888"/>
                    <TextBlock x:Name="TxtInitialSpace" Text="Calculating..." FontSize="18" FontWeight="Bold" Foreground="#FFFFFF" Margin="0,6,0,0"/>
                </StackPanel>
            </Border>

            <Border Grid.Column="2" Background="#2D2D30" CornerRadius="6" Padding="15">
                <StackPanel>
                    <TextBlock Text="DRIVE HEALTH" FontSize="11" FontWeight="Bold" Foreground="#888888"/>
                    <TextBlock x:Name="TxtDriveHealth" Text="Checking..." FontSize="18" FontWeight="Bold" Foreground="#00E5FF" Margin="0,6,0,0"/>
                </StackPanel>
            </Border>

            <Border Grid.Column="4" Background="#2D2D30" CornerRadius="6" Padding="15">
                <StackPanel>
                    <TextBlock Text="TEMP" FontSize="11" FontWeight="Bold" Foreground="#888888"/>
                    <TextBlock x:Name="TxtDriveTemp" Text="-- °C" FontSize="18" FontWeight="Bold" Foreground="#FFCC00" Margin="0,6,0,0"/>
                </StackPanel>
            </Border>
        </Grid>

        <!-- Task Selection Checkboxes & Profile Buttons -->
        <Border Grid.Row="2" Background="#252526" CornerRadius="6" Padding="12" Margin="0,0,0,15">
            <StackPanel>
                <Grid Margin="0,0,0,10">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" Text="SELECT TASKS TO RUN" FontSize="11" FontWeight="Bold" Foreground="#888888" VerticalAlignment="Center"/>
                    
                    <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                        <TextBlock Text="PROFILES:" FontSize="11" FontWeight="Bold" Foreground="#888888" VerticalAlignment="Center" Margin="0,0,10,0"/>
                        <Button x:Name="BtnProfileDefault" Content="Default" Width="80" Height="26" 
                                Background="#007ACC" Foreground="White" FontSize="11" FontWeight="Bold" BorderThickness="0" Margin="0,0,6,0" Cursor="Hand">
                            <Button.Resources>
                                <Style TargetType="Border"><Setter Property="CornerRadius" Value="4"/></Style>
                            </Button.Resources>
                        </Button>
                        <Button x:Name="BtnProfileServer" Content="Server Cleanup" Width="105" Height="26" 
                                Background="#2D2D30" Foreground="#AAAAAA" FontSize="11" FontWeight="Bold" BorderThickness="0" Margin="0,0,6,0" Cursor="Hand">
                            <Button.Resources>
                                <Style TargetType="Border"><Setter Property="CornerRadius" Value="4"/></Style>
                            </Button.Resources>
                        </Button>
                        <Button x:Name="BtnProfileCustom" Content="Custom" Width="80" Height="26" 
                                Background="#2D2D30" Foreground="#AAAAAA" FontSize="11" FontWeight="Bold" BorderThickness="0" Cursor="Hand">
                            <Button.Resources>
                                <Style TargetType="Border"><Setter Property="CornerRadius" Value="4"/></Style>
                            </Button.Resources>
                        </Button>
                    </StackPanel>
                </Grid>

                <WrapPanel>
                    <CheckBox x:Name="ChkTempFiles" Content="Clear Temp Files &amp; System Logs" IsChecked="True" Foreground="#FFFFFF" Margin="0,0,15,5" Cursor="Hand"/>
                    <CheckBox x:Name="ChkRecycleBin" Content="Empty Recycle Bin" IsChecked="True" Foreground="#FFFFFF" Margin="0,0,15,5" Cursor="Hand"/>
                    <CheckBox x:Name="ChkCleanmgr" Content="Run Disk Cleanup Utility" IsChecked="True" Foreground="#FFFFFF" Margin="0,0,15,5" Cursor="Hand"/>
                    <CheckBox x:Name="ChkFlushDNS" Content="Flush DNS Cache" IsChecked="True" Foreground="#FFFFFF" Margin="0,0,15,5" Cursor="Hand"/>
                    <CheckBox x:Name="ChkDism" Content="DISM Component Store Cleanup" IsChecked="True" Foreground="#FFFFFF" Margin="0,0,15,5" Cursor="Hand"/>
                </WrapPanel>
            </StackPanel>
        </Border>

        <!-- Output Log Terminal -->
        <Border Grid.Row="3" Background="#0C0C0C" BorderBrush="#333333" BorderThickness="1" CornerRadius="6" Padding="12">
            <ScrollViewer x:Name="LogScroll" VerticalScrollBarVisibility="Auto">
                <TextBox x:Name="TxtLog" Background="Transparent" Foreground="#00FF66" BorderThickness="0" 
                         FontFamily="Consolas" FontSize="13" IsReadOnly="True" TextWrapping="Wrap"/>
            </ScrollViewer>
        </Border>

        <!-- Reclaimed Storage Box -->
        <Border Grid.Row="4" Background="#2D2D30" CornerRadius="6" Padding="15" Margin="0,15,0,0">
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

        <!-- Progress Bar with Percentage Overlay -->
        <Grid Grid.Row="5" Height="18" Margin="0,15,0,15">
            <ProgressBar x:Name="CleanProgress" Foreground="#00E5FF" Background="#2D2D30" BorderThickness="0" Value="0" Maximum="100"/>
            <TextBlock x:Name="TxtProgressPercent" Text="0%" Foreground="#FFFFFF" FontSize="11" FontWeight="Bold" 
                       HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Grid>

        <!-- Action Controls -->
        <Grid Grid.Row="6">
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
$ImgLogo            = $Window.FindName("ImgLogo")
$ImgLogoRight       = $Window.FindName("ImgLogoRight")
$TxtVersion         = $Window.FindName("TxtVersion")
$TxtInitialSpace    = $Window.FindName("TxtInitialSpace")
$TxtReclaimed       = $Window.FindName("TxtReclaimed")
$TxtDriveHealth     = $Window.FindName("TxtDriveHealth")
$TxtDriveTemp       = $Window.FindName("TxtDriveTemp")
$TxtLog             = $Window.FindName("TxtLog")
$LogScroll          = $Window.FindName("LogScroll")
$CleanProgress      = $Window.FindName("CleanProgress")
$TxtProgressPercent = $Window.FindName("TxtProgressPercent")
$TxtStatus          = $Window.FindName("TxtStatus")
$BtnStart           = $Window.FindName("BtnStart")

# Map Profile Buttons
$BtnProfileDefault  = $Window.FindName("BtnProfileDefault")
$BtnProfileServer   = $Window.FindName("BtnProfileServer")
$BtnProfileCustom   = $Window.FindName("BtnProfileCustom")

# Map Task Checkboxes
$ChkTempFiles       = $Window.FindName("ChkTempFiles")
$ChkRecycleBin      = $Window.FindName("ChkRecycleBin")
$ChkCleanmgr        = $Window.FindName("ChkCleanmgr")
$ChkFlushDNS        = $Window.FindName("ChkFlushDNS")
$ChkDism            = $Window.FindName("ChkDism")

# Brushes for Profile Highlighting
$BrushActiveBG    = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#007ACC")
$BrushInactiveBG  = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#2D2D30")
$BrushActiveFG    = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFFFFF")
$BrushInactiveFG  = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#AAAAAA")

$Global:IsUpdatingProfile = $false

function Save-LogAndMaintainHistory {
    try {
        if (-not (Test-Path $Global:LogDir)) {
            New-Item -Path $Global:LogDir -ItemType Directory -Force | Out-Null
        }

        # Save current session terminal log
        $TimeStamp = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
        $LogFilePath = Join-Path $Global:LogDir "Cleanup_$TimeStamp.log"
        $TxtLog.Text | Out-File -FilePath $LogFilePath -Encoding utf8 -Force

        Write-GuiLog "Log saved to: $LogFilePath"

        # Rotate logs to retain only the 5 newest files
        $LogFiles = Get-ChildItem -Path $Global:LogDir -Filter "Cleanup_*.log" | Sort-Object CreationTime -Descending
        if ($LogFiles.Count -gt 5) {
            $LogsToDelete = $LogFiles | Select-Object -Skip 5
            foreach ($OldLog in $LogsToDelete) {
                Remove-Item $OldLog.FullName -Force -ErrorAction SilentlyContinue
                Write-GuiLog "Purged old log file: $($OldLog.Name)"
            }
        }
    } catch {
        Write-GuiLog "Note: Could not save log to disk."
    }
}

function Set-ActiveProfileButton ($Profile) {
    $BtnProfileDefault.Background = if ($Profile -eq "Default") { $BrushActiveBG } else { $BrushInactiveBG }
    $BtnProfileDefault.Foreground = if ($Profile -eq "Default") { $BrushActiveFG } else { $BrushInactiveFG }

    $BtnProfileServer.Background  = if ($Profile -eq "Server")  { $BrushActiveBG } else { $BrushInactiveBG }
    $BtnProfileServer.Foreground  = if ($Profile -eq "Server")  { $BrushActiveFG } else { $BrushInactiveFG }

    $BtnProfileCustom.Background  = if ($Profile -eq "Custom")  { $BrushActiveBG } else { $BrushInactiveBG }
    $BtnProfileCustom.Foreground  = if ($Profile -eq "Custom")  { $BrushActiveFG } else { $BrushInactiveFG }
}

function Evaluate-CurrentProfile {
    if ($Global:IsUpdatingProfile) { return }

    if ($ChkTempFiles.IsChecked -and $ChkRecycleBin.IsChecked -and $ChkCleanmgr.IsChecked -and $ChkFlushDNS.IsChecked -and $ChkDism.IsChecked) {
        Set-ActiveProfileButton "Default"
    }
    elseif ($ChkTempFiles.IsChecked -and $ChkRecycleBin.IsChecked -and $ChkCleanmgr.IsChecked -and (-not $ChkFlushDNS.IsChecked) -and (-not $ChkDism.IsChecked)) {
        Set-ActiveProfileButton "Server"
    }
    else {
        Set-ActiveProfileButton "Custom"
    }
}

# Attach Checkbox Change Event Handlers
$AllCheckboxes = @($ChkTempFiles, $ChkRecycleBin, $ChkCleanmgr, $ChkFlushDNS, $ChkDism)
foreach ($Chk in $AllCheckboxes) {
    $Chk.Add_Checked({ Evaluate-CurrentProfile })
    $Chk.Add_Unchecked({ Evaluate-CurrentProfile })
}

# Profile Button Click Handlers
$BtnProfileDefault.Add_Click({
    $Global:IsUpdatingProfile = $true
    $ChkTempFiles.IsChecked  = $true
    $ChkRecycleBin.IsChecked = $true
    $ChkCleanmgr.IsChecked   = $true
    $ChkFlushDNS.IsChecked   = $true
    $ChkDism.IsChecked       = $true
    Set-ActiveProfileButton "Default"
    $Global:IsUpdatingProfile = $false
})

$BtnProfileServer.Add_Click({
    $Global:IsUpdatingProfile = $true
    $ChkTempFiles.IsChecked  = $true
    $ChkRecycleBin.IsChecked = $true
    $ChkCleanmgr.IsChecked   = $true
    $ChkFlushDNS.IsChecked   = $false
    $ChkDism.IsChecked       = $false
    Set-ActiveProfileButton "Server"
    $Global:IsUpdatingProfile = $false
})

$BtnProfileCustom.Add_Click({
    Set-ActiveProfileButton "Custom"
})

function Write-GuiLog ($Message) {
    if ([string]::IsNullOrWhiteSpace($Message)) { return }
    $TxtLog.AppendText("[$((Get-Date).ToString('HH:mm:ss'))] $Message`n")
    $LogScroll.ScrollToEnd()
}

# --- DIRECT HARDWARE SMART DIAGNOSTICS ---
function Get-DriveHealthDiagnostics {
    Write-GuiLog "=== DISK HEALTH & SMART DIAGNOSTICS ==="
    $HealthStatusText = "Healthy"
    $TempStatusText = "N/A"

    try {
        $PhysicalDisks = Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue

        foreach ($Disk in $PhysicalDisks) {
            $Model = $Disk.Model
            $Index = $Disk.Index
            $Interface = $Disk.InterfaceType
            $Status = $Disk.Status

            Write-GuiLog "Drive [$Index]: $Model ($Interface) - SMART Status: $Status"
            
            if ($TempStatusText -eq "N/A") {
                $PhysDisk = Get-PhysicalDisk | Where-Object { $_.DeviceId -eq $Index } -ErrorAction SilentlyContinue
                if ($PhysDisk) {
                    $Counter = $PhysDisk | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
                    if ($Counter -and $Counter.Temperature -gt 0) {
                        $TempStatusText = "$($Counter.Temperature) °C"
                    }
                    if ($Counter -and $Counter.Wear -ne $null) {
                        $HealthStatusText = "$(100 - $Counter.Wear)% Health"
                    }
                }
            }
        }
    } catch {
        $HealthStatusText = "Healthy"
    }

    $TxtDriveHealth.Text = $HealthStatusText
    $TxtDriveTemp.Text = $TempStatusText
}

function Check-ForUpdates {
    Write-GuiLog "Checking for updates..."
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) PowerShell-App"
        $Url = "https://api.github.com/repos/$Global:RepoName/releases"

        $Releases = Invoke-RestMethod -Uri $Url -Method Get -UserAgent $UserAgent -ErrorAction Stop
        $StableReleases = $Releases | Where-Object { $_.prerelease -eq $false }
        $LocalVersion = [version]($Global:CurrentVersion.ToLower().TrimStart('v').Split("-")[0])

        foreach ($Rel in $StableReleases) {
            $RemoteVersion = [version]($Rel.tag_name.ToLower().TrimStart('v').Split("-")[0])
            if ($RemoteVersion -gt $LocalVersion) {
                Write-GuiLog "[!] UPDATE AVAILABLE: $($Rel.tag_name)"
                break 
            }
        }
        Write-GuiLog "Running stable version (v$Global:CurrentVersion)."
    } catch {
        Write-GuiLog "Note: Update check skipped."
    }
}

$Window.Add_Loaded({
    try {
        $Hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($Window)).Handle
        $DarkTealColor = 0x00382D12 
        [Win32.DwmApi]::DwmSetWindowAttribute($Hwnd, 35, [ref]$DarkTealColor, [System.Runtime.InteropServices.Marshal]::SizeOf([type][int])) | Out-Null
    } catch {}

    $LogoPath = Join-Path $CurrentDir "Logo.jpg"
    if (Test-Path $LogoPath) {
        $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
        $bitmap.BeginInit()
        $bitmap.UriSource = New-Object System.Uri($LogoPath, [System.UriKind]::Absolute)
        $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bitmap.EndInit()
        $ImgLogo.Source = $bitmap
    }

    $LogoRightPath = Join-Path $CurrentDir "LogoRight.jpg"
    if (Test-Path $LogoRightPath) {
        $bitmapRight = New-Object System.Windows.Media.Imaging.BitmapImage
        $bitmapRight.BeginInit()
        $bitmapRight.UriSource = New-Object System.Uri($LogoRightPath, [System.UriKind]::Absolute)
        $bitmapRight.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bitmapRight.EndInit()
        $ImgLogoRight.Source = $bitmapRight
    }

    $TxtVersion.Text = "v$Global:CurrentVersion"
    $Drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $Global:StartingFreeSpace = $Drive.FreeSpace
    $TxtInitialSpace.Text = "$([Math]::Round($Global:StartingFreeSpace / 1GB, 2)) GB"
    
    Write-GuiLog "System Cleanup Initialized."
    Get-DriveHealthDiagnostics
    Check-ForUpdates
})

# --- ASYNCHRONOUS RUNSPACE WORKER ---
$BtnStart.Add_Click({
    # Read state of task selections
    $SelectedTasks = @{
        DoTemp      = $ChkTempFiles.IsChecked
        DoRecycle   = $ChkRecycleBin.IsChecked
        DoCleanmgr  = $ChkCleanmgr.IsChecked
        DoFlushDNS  = $ChkFlushDNS.IsChecked
        DoDism      = $ChkDism.IsChecked
    }

    $TotalSelected = ($SelectedTasks.Values | Where-Object { $_ -eq $true }).Count
    if ($TotalSelected -eq 0) {
        $TxtStatus.Text = "Please select at least one task to run."
        return
    }

    $BtnStart.IsEnabled = $false
    $BtnStart.Content = "Cleaning..."
    $CleanProgress.Value = 0
    $TxtProgressPercent.Text = "0%"
    
    # Disable controls during cleanup
    $BtnProfileDefault.IsEnabled = $false
    $BtnProfileServer.IsEnabled  = $false
    $BtnProfileCustom.IsEnabled  = $false
    $ChkTempFiles.IsEnabled      = $false
    $ChkRecycleBin.IsEnabled     = $false
    $ChkCleanmgr.IsEnabled       = $false
    $ChkFlushDNS.IsEnabled       = $false
    $ChkDism.IsEnabled           = $false

    $Global:LogQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
    $Global:ProgressQueue = [System.Collections.Concurrent.ConcurrentQueue[hashtable]]::new()
    $Global:FinishedQueue = [System.Collections.Concurrent.ConcurrentQueue[bool]]::new()

    $ScriptBlock = {
        param($CurrentDir, $RegFiles, $SelectedTasks, $LogQueue, $ProgressQueue, $FinishedQueue)

        function Send-Log ($msg) {
            if (-not [string]::IsNullOrWhiteSpace($msg)) {
                $LogQueue.Enqueue($msg)
            }
        }
        function Send-Progress ($val, $status) {
            $ProgressQueue.Enqueue(@{ Value = $val; Status = $status })
        }

        # Safe Thread-Compatible Process Runner
        function Run-SilentProcess ($FileName, $Arguments) {
            try {
                $pinfo = New-Object System.Diagnostics.ProcessStartInfo
                $pinfo.FileName = $FileName
                $pinfo.Arguments = $Arguments
                $pinfo.UseShellExecute = $false
                $pinfo.RedirectStandardOutput = $true
                $pinfo.RedirectStandardError = $true
                $pinfo.CreateNoWindow = $true

                $p = New-Object System.Diagnostics.Process
                $p.StartInfo = $pinfo
                $p.Start() | Out-Null

                while (-not $p.StandardOutput.EndOfStream) {
                    $line = $p.StandardOutput.ReadLine()
                    if ($line) { Send-Log $line.Trim() }
                }
                $p.WaitForExit()
                $p.Close()
            } catch {
                Send-Log "Task ($FileName) finished."
            }
        }

        $TotalTasks = ($SelectedTasks.Values | Where-Object { $_ -eq $true }).Count
        $CompletedTasks = 0

        # Always apply registry prep settings automatically
        foreach ($File in $RegFiles) {
            $FilePath = Join-Path $CurrentDir $File
            if (Test-Path $FilePath) {
                Run-SilentProcess "reg.exe" "import `"$FilePath`""
            }
        }

        # 1. Clear Temp Files
        if ($SelectedTasks.DoTemp) {
            $StartPercent = [Math]::Round(($CompletedTasks / $TotalTasks) * 100)
            Send-Progress $StartPercent "Clearing temporary files..."
            Send-Log "=== CLEARING TEMP FILES AND LOGS ==="
            $TargetFolders = @(
                "C:\Windows\Temp\*", "C:\Windows\Prefetch\*", 
                "C:\Windows\SoftwareDistribution\Download\*", 
                "$([System.IO.Path]::GetTempPath())*", "C:\Intel", "C:\PerfLogs"
            )
            foreach ($Path in $TargetFolders) {
                if (Test-Path $Path) {
                    Send-Log "Deleting files in: $Path"
                    Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            $CompletedTasks++
            $EndPercent = [Math]::Round(($CompletedTasks / $TotalTasks) * 100)
            Send-Progress $EndPercent "Temp files cleared."
        }

        # 2. Empty Recycle Bin
        if ($SelectedTasks.DoRecycle) {
            $StartPercent = [Math]::Round(($CompletedTasks / $TotalTasks) * 100)
            Send-Progress $StartPercent "Emptying Recycle Bin..."
            Send-Log "=== EMPTYING RECYCLE BIN ==="
            Clear-RecycleBin -Force -ErrorAction SilentlyContinue
            Send-Log "Recycle bin emptied."
            $CompletedTasks++
            $EndPercent = [Math]::Round(($CompletedTasks / $TotalTasks) * 100)
            Send-Progress $EndPercent "Recycle bin emptied."
        }

        # 3. Disk Cleanup Utility
        if ($SelectedTasks.DoCleanmgr) {
            $StartPercent = [Math]::Round(($CompletedTasks / $TotalTasks) * 100)
            Send-Progress $StartPercent "Running Disk Cleanup Utility..."
            Send-Log "=== RUNNING CLEANMGR UTILITY ==="
            $CleanParam = if (Test-Path "C:\Windows.old") { "/SAGERUN:1" } else { "/SAGERUN:2" }
            Run-SilentProcess "cleanmgr.exe" $CleanParam
            $CompletedTasks++
            $EndPercent = [Math]::Round(($CompletedTasks / $TotalTasks) * 100)
            Send-Progress $EndPercent "Disk cleanup complete."
        }

        # 4. Flush DNS
        if ($SelectedTasks.DoFlushDNS) {
            $StartPercent = [Math]::Round(($CompletedTasks / $TotalTasks) * 100)
            Send-Progress $StartPercent "Flushing DNS Cache..."
            Send-Log "=== FLUSHING DNS CACHE ==="
            Run-SilentProcess "ipconfig.exe" "/flushdns"
            $CompletedTasks++
            $EndPercent = [Math]::Round(($CompletedTasks / $TotalTasks) * 100)
            Send-Progress $EndPercent "DNS Cache flushed."
        }

        # 5. DISM Optimization
        if ($SelectedTasks.DoDism) {
            $StartPercent = [Math]::Round(($CompletedTasks / $TotalTasks) * 100)
            Send-Progress $StartPercent "Optimizing DISM Component Store..."
            Send-Log "=== RUNNING DISM COMPONENT STORE CLEANUP ==="
            Run-SilentProcess "Dism.exe" "/online /Cleanup-Image /StartComponentCleanup /ResetBase /NoRestart /English"
            $CompletedTasks++
            $EndPercent = [Math]::Round(($CompletedTasks / $TotalTasks) * 100)
            Send-Progress $EndPercent "DISM cleanup complete."
        }

        Send-Progress 100 "Optimization Complete!"
        $FinishedQueue.Enqueue($true)
    }

    $Global:Runspace = [runspacefactory]::CreateRunspace()
    $Global:Runspace.Open()
    $Global:PowerShell = [powershell]::Create()
    $Global:PowerShell.Runspace = $Global:Runspace
    [void]$Global:PowerShell.AddScript($ScriptBlock)
    [void]$Global:PowerShell.AddArgument($CurrentDir)
    [void]$Global:PowerShell.AddArgument($Global:RegFiles)
    [void]$Global:PowerShell.AddArgument($SelectedTasks)
    [void]$Global:PowerShell.AddArgument($Global:LogQueue)
    [void]$Global:PowerShell.AddArgument($Global:ProgressQueue)
    [void]$Global:PowerShell.AddArgument($Global:FinishedQueue)
    
    $Global:AsyncResult = $Global:PowerShell.BeginInvoke()

    $Timer = New-Object System.Windows.Threading.DispatcherTimer
    $Timer.Interval = [TimeSpan]::FromMilliseconds(50)

    $Timer.Add_Tick({
        param($sender, $e)

        $msg = ""
        while ($Global:LogQueue.TryDequeue([ref]$msg)) {
            Write-GuiLog $msg
        }

        $prog = $null
        while ($Global:ProgressQueue.TryDequeue([ref]$prog)) {
            $CleanProgress.Value = $prog.Value
            $TxtProgressPercent.Text = "$($prog.Value)%"
            $TxtStatus.Text = $prog.Status
        }

        $isDone = $false
        if ($Global:FinishedQueue.TryDequeue([ref]$isDone) -or ($Global:AsyncResult -and $Global:AsyncResult.IsCompleted)) {
            # Flush output queues before finishing
            while ($Global:LogQueue.TryDequeue([ref]$msg)) { Write-GuiLog $msg }
            while ($Global:ProgressQueue.TryDequeue([ref]$prog)) {
                $CleanProgress.Value = $prog.Value
                $TxtProgressPercent.Text = "$($prog.Value)%"
                $TxtStatus.Text = $prog.Status
            }

            $sender.Stop()
            
            try { if ($Global:PowerShell) { $Global:PowerShell.EndInvoke($Global:AsyncResult) } } catch {}
            try { if ($Global:PowerShell) { $Global:PowerShell.Dispose() } } catch {}
            try { if ($Global:Runspace) { $Global:Runspace.Dispose() } } catch {}

            $DriveEnd = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
            $SpaceSavedBytes = $DriveEnd.FreeSpace - $Global:StartingFreeSpace
            $ReadableSpace = if ($SpaceSavedBytes -le 0) { "0 MB" } elseif ($SpaceSavedBytes -gt 1GB) { "$([Math]::Round($SpaceSavedBytes / 1GB, 2)) GB" } else { "$([Math]::Round($SpaceSavedBytes / 1MB, 2)) MB" }

            $TxtReclaimed.Text = $ReadableSpace
            
            # Re-enable controls
            $BtnStart.IsEnabled = $true
            $BtnStart.Content = "Finished"
            $BtnStart.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#28A745")

            $BtnProfileDefault.IsEnabled = $true
            $BtnProfileServer.IsEnabled  = $true
            $BtnProfileCustom.IsEnabled  = $true
            $ChkTempFiles.IsEnabled      = $true
            $ChkRecycleBin.IsEnabled     = $true
            $ChkCleanmgr.IsEnabled       = $true
            $ChkFlushDNS.IsEnabled       = $true
            $ChkDism.IsEnabled           = $true
            
            Write-GuiLog "=== CLEANUP COMPLETE! TOTAL STORAGE RECLAIMED: $ReadableSpace ==="
            
            # Automatically save the session log and trim log history to 5 files
            Save-LogAndMaintainHistory
        }
    })

    $Timer.Start()
})

$Window.ShowDialog() | Out-Null