# --- 1. Administrator Check (Self-Elevating) ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $ExePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    if ($ExePath -like "*.exe" -and $ExePath -notlike "*powershell*") {
        Start-Process -FilePath $ExePath -Verb RunAs
    } else {
        $ScriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Definition }
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`"" -Verb RunAs
    }
    Exit
}

# --- TERMINAL ASCII LOGO BANNER ---
Clear-Host
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Teal = "DarkCyan"

Write-Host "                ,▄▄██████████▄▄,                " -ForegroundColor $Teal
Write-Host "             ▄████▀▀▀        ▀▀████▄            " -ForegroundColor $Teal
Write-Host "           ████▀                ▀███▄         " -ForegroundColor $Teal
Write-Host "         ▄███▀          ▓▓        ▀███▄       " -ForegroundColor $Teal
Write-Host "        ███▀           ▓▓            ▀███     " -ForegroundColor $Teal
Write-Host "       ███            ▓▓               ███     " -ForegroundColor $Teal
Write-Host "      ███            ▓▓                 ███    " -ForegroundColor $Teal
Write-Host "      ███          ▄███▄          ░░     ███    " -ForegroundColor $Teal
Write-Host "      ███   •     ███████        ░░░     ███    " -ForegroundColor $Teal
Write-Host "      ███  •●    █████████     ══        ███    " -ForegroundColor $Teal
Write-Host "      ███ ▄▄█▄  ███████████   ═══        ███    " -ForegroundColor $Teal
Write-Host "       ███ ▀▀  █████████████            ███     " -ForegroundColor $Teal
Write-Host "        ███▄   ▀▀▀▀▀▀▀▀▀▀▀▀▀          ▄███      " -ForegroundColor $Teal
Write-Host "         ▀███▄ ════════════════════ ▄███▀       " -ForegroundColor $Teal
Write-Host "           ▀████▄                ▄████▀         " -ForegroundColor $Teal
Write-Host "             ▀██████████████████████▀           " -ForegroundColor $Teal
Write-Host "                ▀▀▀████████████▀▀▀              " -ForegroundColor $Teal
Write-Host "`n Starting Myles Mattlock CleanUp Tool GUI...`n" -ForegroundColor Gray

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# --- NATIVE WINDOW DWM COLORING ---
Add-Type -MemberDefinition @"
    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
"@ -Name "DwmApi" -Namespace "Win32" | Out-Null

# --- CONFIGURATION ---
$Global:CurrentVersion = "3.0.0" 
$Global:RepoName = "Myles-Mattlock/CleanUp-Tool"
$Global:RegFiles = @("DiskCleanupSettings.reg", "DiskCleanupSettings2.reg") 
$Global:LogDir = "C:\Program Files\SystemCleanUp\Logs"

if ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName -like "*.exe" -and [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName -notlike "*powershell*") {
    $CurrentDir = [System.IO.Path]::GetDirectoryName([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
} elseif ($PSCommandPath) {
    $CurrentDir = Split-Path -Parent $PSCommandPath
} else {
    $CurrentDir = Get-Location
}

# --- XAML UI DESIGN ---
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Myles Mattlock CleanUp Tool" Height="860" Width="960" 
        WindowStartupLocation="CenterScreen" Background="#1E1E1E" Foreground="#FFFFFF"
        ResizeMode="CanMinimize">
    <Window.Resources>
        <Style x:Key="ProfileButtonStyle" TargetType="Button">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}" CornerRadius="4">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" x:Name="contentPresenter"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="border" Property="Background" Value="{Binding Background, RelativeSource={RelativeSource TemplatedParent}}"/>
                                <Setter Property="Foreground" Value="{Binding Foreground, RelativeSource={RelativeSource TemplatedParent}}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="StartButtonStyle" TargetType="Button">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}" CornerRadius="6">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" x:Name="contentPresenter"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <MultiTrigger>
                                <MultiTrigger.Conditions>
                                    <Condition Property="IsMouseOver" Value="True"/>
                                    <Condition Property="Content" Value="Start Cleanup"/>
                                </MultiTrigger.Conditions>
                                <Setter TargetName="border" Property="Background" Value="#0098FF"/>
                            </MultiTrigger>
                            <MultiTrigger>
                                <MultiTrigger.Conditions>
                                    <Condition Property="IsMouseOver" Value="True"/>
                                    <Condition Property="Content" Value="Finished"/>
                                </MultiTrigger.Conditions>
                                <Setter TargetName="border" Property="Background" Value="#33FF88"/>
                            </MultiTrigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="border" Property="Background" Value="#444444"/>
                                <Setter Property="Foreground" Value="#FFFFFF"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid Margin="25">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
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

        <!-- Top Stats Bar StackPanel for Separate Drive Rows -->
        <StackPanel x:Name="DriveStatsPanel" Grid.Row="1" Margin="0,0,0,15"/>

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
                        <Button x:Name="BtnProfileDefault" Content="Default" Width="80" Height="26" Style="{StaticResource ProfileButtonStyle}" Background="#007ACC" Foreground="White" FontSize="11" FontWeight="Bold" BorderThickness="0" Margin="0,0,6,0" Cursor="Hand"/>
                        <Button x:Name="BtnProfileServer" Content="Server Cleanup" Width="105" Height="26" Style="{StaticResource ProfileButtonStyle}" Background="#2D2D30" Foreground="#AAAAAA" FontSize="11" FontWeight="Bold" BorderThickness="0" Margin="0,0,6,0" Cursor="Hand"/>
                        <Button x:Name="BtnProfileCustom" Content="Custom" Width="80" Height="26" Style="{StaticResource ProfileButtonStyle}" Background="#2D2D30" Foreground="#AAAAAA" FontSize="11" FontWeight="Bold" BorderThickness="0" Cursor="Hand"/>
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
                <TextBox x:Name="TxtLog" Background="Transparent" Foreground="#00FF66" BorderThickness="0" FontFamily="Consolas" FontSize="13" IsReadOnly="True" TextWrapping="Wrap"/>
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
            <ProgressBar x:Name="CleanProgress" Foreground="#007ACC" Background="#2D2D30" BorderThickness="0" Value="0" Maximum="100"/>
            <TextBlock x:Name="TxtProgressPercent" Text="0%" Foreground="#FFFFFF" FontSize="11" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Grid>

        <!-- Action Controls -->
        <Grid Grid.Row="6">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock x:Name="TxtStatus" Text="Ready to start cleanup." VerticalAlignment="Center" Foreground="#AAAAAA" FontSize="14"/>
            <Button x:Name="BtnStart" Grid.Column="1" Content="Start Cleanup" Width="160" Height="42" 
                    Style="{StaticResource StartButtonStyle}" Background="#007ACC" Foreground="White" FontSize="14" FontWeight="Bold" BorderThickness="0" Cursor="Hand"/>
        </Grid>
    </Grid>
</Window>
"@

# Load XAML & Map UI Controls
$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$Window = [Windows.Markup.XamlReader]::Load($reader)

@("ImgLogo", "ImgLogoRight", "TxtVersion", "DriveStatsPanel", "TxtReclaimed",
  "TxtLog", "LogScroll", "CleanProgress", "TxtProgressPercent", "TxtStatus", "BtnStart",
  "BtnProfileDefault", "BtnProfileServer", "BtnProfileCustom",
  "ChkTempFiles", "ChkRecycleBin", "ChkCleanmgr", "ChkFlushDNS", "ChkDism") | ForEach-Object {
    Set-Variable -Name $_ -Value $Window.FindName($_)
}

$TaskCheckboxes = @($ChkTempFiles, $ChkRecycleBin, $ChkCleanmgr, $ChkFlushDNS, $ChkDism)
$InteractiveControls = $TaskCheckboxes + @($BtnProfileDefault, $BtnProfileServer, $BtnProfileCustom)

# Brushes
$BrushActiveBG    = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#007ACC")
$BrushActiveHover = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0098FF")
$BrushInactiveBG  = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#2D2D30")
$BrushInactiveHvr = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#3E3E42")
$BrushActiveFG    = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFFFFF")
$BrushInactiveFG  = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#AAAAAA")

# Finish Button Brushes
$BrushFinishBG    = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#00FF66")
$BrushFinishFG    = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#000000")

$Global:IsUpdatingProfile = $false
$Global:DriveUIMap = @{}

function Save-LogAndMaintainHistory {
    try {
        if (-not (Test-Path $Global:LogDir)) { New-Item -Path $Global:LogDir -ItemType Directory -Force | Out-Null }
        $LogFilePath = Join-Path $Global:LogDir "Cleanup_$((Get-Date).ToString('yyyy-MM-dd_HH-mm-ss')).log"
        $TxtLog.Text | Out-File -FilePath $LogFilePath -Encoding utf8 -Force
        Write-GuiLog "Log saved to: $LogFilePath"

        $LogFiles = Get-ChildItem -Path $Global:LogDir -Filter "Cleanup_*.log" | Sort-Object CreationTime -Descending
        if ($LogFiles.Count -gt 5) {
            $LogFiles | Select-Object -Skip 5 | ForEach-Object {
                Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
                Write-GuiLog "Purged old log file: $($_.Name)"
            }
        }
    } catch { Write-GuiLog "Note: Could not save log to disk." }
}

function Set-ActiveProfileButton ($ProfileMode) {
    $BtnProfileDefault.Background = if ($ProfileMode -eq "Default") { $BrushActiveBG } else { $BrushInactiveBG }
    $BtnProfileDefault.Foreground = if ($ProfileMode -eq "Default") { $BrushActiveFG } else { $BrushInactiveFG }
    $BtnProfileServer.Background  = if ($ProfileMode -eq "Server")  { $BrushActiveBG } else { $BrushInactiveBG }
    $BtnProfileServer.Foreground  = if ($ProfileMode -eq "Server")  { $BrushActiveFG } else { $BrushInactiveFG }
    $BtnProfileCustom.Background  = if ($ProfileMode -eq "Custom")  { $BrushActiveBG } else { $BrushInactiveBG }
    $BtnProfileCustom.Foreground  = if ($ProfileMode -eq "Custom")  { $BrushActiveFG } else { $BrushInactiveFG }
}

function Invoke-CurrentProfileEvaluation {
    if ($Global:IsUpdatingProfile -or (-not $BtnStart.IsEnabled)) { return }
    if ($ChkTempFiles.IsChecked -and $ChkRecycleBin.IsChecked -and $ChkCleanmgr.IsChecked -and $ChkFlushDNS.IsChecked -and $ChkDism.IsChecked) { Set-ActiveProfileButton "Default" }
    elseif ($ChkTempFiles.IsChecked -and $ChkRecycleBin.IsChecked -and $ChkCleanmgr.IsChecked -and (-not $ChkFlushDNS.IsChecked) -and (-not $ChkDism.IsChecked)) { Set-ActiveProfileButton "Server" }
    else { Set-ActiveProfileButton "Custom" }
}

# Attach Hover & Checkbox Events
@($BtnProfileDefault, $BtnProfileServer, $BtnProfileCustom) | ForEach-Object {
    $_.Add_MouseEnter({
        if (-not $BtnStart.IsEnabled) { return }
        $this.Background = if ($this.Background.ToString() -eq $BrushActiveBG.ToString()) { $BrushActiveHover } else { $BrushInactiveHvr }
        if ($this.Background.ToString() -ne $BrushActiveHover.ToString()) { $this.Foreground = $BrushActiveFG }
    })
    $_.Add_MouseLeave({ if ($BtnStart.IsEnabled) { Invoke-CurrentProfileEvaluation } })
}

$TaskCheckboxes | ForEach-Object {
    $_.Add_Checked({ Invoke-CurrentProfileEvaluation })
    $_.Add_Unchecked({ Invoke-CurrentProfileEvaluation })
}

# Profile Clicks
$BtnProfileDefault.Add_Click({
    if (-not $BtnStart.IsEnabled) { return }
    $Global:IsUpdatingProfile = $true
    $TaskCheckboxes | ForEach-Object { $_.IsChecked = $true }
    Set-ActiveProfileButton "Default"
    $Global:IsUpdatingProfile = $false
})

$BtnProfileServer.Add_Click({
    if (-not $BtnStart.IsEnabled) { return }
    $Global:IsUpdatingProfile = $true
    $ChkTempFiles.IsChecked = $ChkRecycleBin.IsChecked = $ChkCleanmgr.IsChecked = $true
    $ChkFlushDNS.IsChecked  = $ChkDism.IsChecked = $false
    Set-ActiveProfileButton "Server"
    $Global:IsUpdatingProfile = $false
})

$BtnProfileCustom.Add_Click({ if ($BtnStart.IsEnabled) { Set-ActiveProfileButton "Custom" } })

function Write-GuiLog ($Message) {
    if ([string]::IsNullOrWhiteSpace($Message)) { return }
    $TxtLog.AppendText("[$((Get-Date).ToString('HH:mm:ss'))] $Message`n")
    $LogScroll.ScrollToEnd()
}

# Build a Dedicated Stat Bar Row per Drive
function Add-DriveRowUI ($DriveLetter, $InitialFreeText) {
    $Grid = New-Object System.Windows.Controls.Grid
    $Grid.Margin = New-Object System.Windows.Thickness(0, 0, 0, 8)

    0..2 | ForEach-Object {
        $col = New-Object System.Windows.Controls.ColumnDefinition
        $col.Width = if ($_ -eq 0) { [System.Windows.GridLength]::new(1.2, [System.Windows.GridUnitType]::Star) } else { [System.Windows.GridLength]::new(1.0, [System.Windows.GridUnitType]::Star) }
        [void]$Grid.ColumnDefinitions.Add($col)
        if ($_ -lt 2) {
            $spaceCol = New-Object System.Windows.Controls.ColumnDefinition
            $spaceCol.Width = [System.Windows.GridLength]::new(15, [System.Windows.GridUnitType]::Pixel)
            [void]$Grid.ColumnDefinitions.Add($spaceCol)
        }
    }

    function Create-Card ($Title, $ValText, $FgHex, $ColIdx) {
        $Border = New-Object System.Windows.Controls.Border
        $Border.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#2D2D30")
        $Border.CornerRadius = New-Object System.Windows.CornerRadius(6)
        $Border.Padding = New-Object System.Windows.Thickness(12)
        [System.Windows.Controls.Grid]::SetColumn($Border, $ColIdx)

        $Stack = New-Object System.Windows.Controls.StackPanel
        $TTitle = New-Object System.Windows.Controls.TextBlock
        $TTitle.Text = $Title; $TTitle.FontSize = 11; $TTitle.FontWeight = [System.Windows.FontWeights]::Bold
        $TTitle.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#888888")

        $TVal = New-Object System.Windows.Controls.TextBlock
        $TVal.Text = $ValText; $TVal.FontSize = 16; $TVal.FontWeight = [System.Windows.FontWeights]::Bold
        $TVal.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($FgHex)
        $TVal.Margin = New-Object System.Windows.Thickness(0, 4, 0, 0)

        [void]$Stack.Children.Add($TTitle)
        [void]$Stack.Children.Add($TVal)
        $Border.Child = $Stack
        return @{ Border = $Border; Text = $TVal }
    }

    $CardSpace  = Create-Card "DRIVE ($DriveLetter) INITIAL FREE" $InitialFreeText "#FFFFFF" 0
    $CardHealth = Create-Card "DRIVE ($DriveLetter) HEALTH" "Checking..." "#00E5FF" 2
    $CardTemp   = Create-Card "DRIVE ($DriveLetter) TEMP" "-- °C" "#FFCC00" 4

    [void]$Grid.Children.Add($CardSpace.Border)
    [void]$Grid.Children.Add($CardHealth.Border)
    [void]$Grid.Children.Add($CardTemp.Border)

    [void]$DriveStatsPanel.Children.Add($Grid)
    $Global:DriveUIMap[$DriveLetter] = @{ Health = $CardHealth.Text; Temp = $CardTemp.Text }
}

# Robust Async Diagnostics Worker
function Request-AsyncDriveStats ($Queue) {
    $Script = {
        param($Q)
        $Results = @()
        try {
            $Disks = Get-PhysicalDisk -ErrorAction SilentlyContinue
            foreach ($Disk in $Disks) {
                $TempStr = "N/A"
                $HealthStr = "100% Health"

                # Query Reliability Counter
                $Rel = $Disk | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
                if ($Rel) {
                    if ($Rel.Temperature -gt 0) { $TempStr = "$($Rel.Temperature) °C" }
                    if ($null -ne $Rel.Wear) { $HealthStr = "$(100 - $Rel.Wear)% Health" }
                }

                # Fallback: Storage Health Report
                if ($TempStr -eq "N/A" -or $HealthStr -eq "100% Health") {
                    try {
                        $Report = $Disk | Get-StorageHealthReport -ErrorAction SilentlyContinue
                        if ($Report) {
                            $TempMetric = $Report.HealthReport | Where-Object { $_.Name -like "*Temperature*" }
                            if ($TempMetric -and $TempMetric.Value -gt 0) { $TempStr = "$($TempMetric.Value) °C" }
                            
                            $WearMetric = $Report.HealthReport | Where-Object { $_.Name -like "*Wear*" -or $_.Name -like "*Percentage Used*" }
                            if ($WearMetric) { $HealthStr = "$(100 - $WearMetric.Value)% Health" }
                        }
                    } catch {}
                }

                # Map Physical Disks to Volumes
                $Partitions = Get-Partition -DiskNumber $Disk.DiskNumber -ErrorAction SilentlyContinue
                foreach ($Part in $Partitions) {
                    if ($Part.DriveLetter) {
                        $Results += @{
                            DriveLetter = "$($Part.DriveLetter):"
                            Health = $HealthStr
                            Temp   = $TempStr
                        }
                    }
                }
            }
        } catch {}

        $Q.Enqueue(@{ Type = "Stats"; Data = $Results })
    }

    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($Script)
    [void]$ps.AddArgument($Queue)
    [void]$ps.BeginInvoke()
}

$Window.Add_Loaded({
    # Instant DWM Window Frame Coloring
    try {
        $Hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($Window)).Handle
        $DarkTealColor = 0x00382D12 
        [Win32.DwmApi]::DwmSetWindowAttribute($Hwnd, 35, [ref]$DarkTealColor, [System.Runtime.InteropServices.Marshal]::SizeOf([type][int])) | Out-Null
    } catch {}

    # Image Load
    @("Logo.jpg", "LogoRight.jpg") | ForEach-Object {
        $Path = Join-Path $CurrentDir $_
        if (Test-Path $Path) {
            $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
            $bmp.BeginInit(); $bmp.UriSource = New-Object System.Uri($Path, [System.UriKind]::Absolute); $bmp.CacheOption = "OnLoad"; $bmp.EndInit()
            if ($_ -eq "Logo.jpg") { $ImgLogo.Source = $bmp } else { $ImgLogoRight.Source = $bmp }
        }
    }

    $TxtVersion.Text = "v$Global:CurrentVersion"
    
    # Render individual rows for each detected fixed drive
    $Drives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady } | Select-Object -First 3
    foreach ($Drive in $Drives) {
        $Letter = $Drive.Name.TrimEnd('\')
        $FreeGB = "$([Math]::Round($Drive.AvailableFreeSpace / 1GB, 2)) GB"
        if ($Letter -eq "C:") { $Global:StartingFreeSpace = $Drive.AvailableFreeSpace }
        Add-DriveRowUI -DriveLetter $Letter -InitialFreeText $FreeGB
    }

    Write-GuiLog "System Cleanup Initialized."

    # GLOBAL INITIALIZATION QUEUE
    $Global:InitQueue = [System.Collections.Concurrent.ConcurrentQueue[hashtable]]::new()

    # ASYNCHRONOUS BACKGROUND STARTUP WORKER (Hardware Diagnostics & Updates)
    $InitScript = {
        param($RepoName, $CurrentVersion, $InitQueue)

        # 1. SMART Hardware Scan Log
        try {
            Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue | ForEach-Object {
                $InitQueue.Enqueue(@{ Type = "Log"; Msg = "Drive [$($_.Index)]: $($_.Model) ($($_.InterfaceType)) - SMART Status: $($_.Status)" })
            }
        } catch {}

        # 2. Check Updates
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $Releases = Invoke-RestMethod -Uri "https://api.github.com/repos/$RepoName/releases" -Method Get -UserAgent "Mozilla/5.0 PowerShell-App" -ErrorAction Stop
            $LocalVersion = [version]($CurrentVersion.ToLower().TrimStart('v').Split("-")[0])
            $HasUpdate = $false
            foreach ($Rel in ($Releases | Where-Object { $_.prerelease -eq $false })) {
                if ([version]($Rel.tag_name.ToLower().TrimStart('v').Split("-")[0]) -gt $LocalVersion) {
                    $InitQueue.Enqueue(@{ Type = "Log"; Msg = "[!] UPDATE AVAILABLE: $($Rel.tag_name)" })
                    $HasUpdate = $true; break
                }
            }
            if (-not $HasUpdate) { $InitQueue.Enqueue(@{ Type = "Log"; Msg = "Running stable version (v$CurrentVersion)." }) }
        } catch { $InitQueue.Enqueue(@{ Type = "Log"; Msg = "Note: Update check skipped." }) }
    }

    $InitRunspace = [runspacefactory]::CreateRunspace()
    $InitRunspace.Open()
    $InitPS = [powershell]::Create()
    $InitPS.Runspace = $InitRunspace
    [void]$InitPS.AddScript($InitScript)
    [void]$InitPS.AddArgument($Global:RepoName)
    [void]$InitPS.AddArgument($Global:CurrentVersion)
    [void]$InitPS.AddArgument($Global:InitQueue)
    $InitAsync = $InitPS.BeginInvoke()

    $InitTimer = New-Object System.Windows.Threading.DispatcherTimer
    $InitTimer.Interval = [TimeSpan]::FromMilliseconds(100)
    $InitTimer.Add_Tick({
        $item = $null
        while ($Global:InitQueue.TryDequeue([ref]$item)) {
            if ($item.Type -eq "Log") { Write-GuiLog $item.Msg }
        }
        if ($InitAsync.IsCompleted) {
            $this.Stop()
            try { $InitPS.Dispose(); $InitRunspace.Dispose() } catch {}
        }
    })
    $InitTimer.Start()

    # --- RECURRING 30-SECOND HARDWARE MONITOR TIMER ---
    $Global:MonitorQueue = [System.Collections.Concurrent.ConcurrentQueue[hashtable]]::new()
    $MonitorTimer = New-Object System.Windows.Threading.DispatcherTimer
    $MonitorTimer.Interval = [TimeSpan]::FromSeconds(30)
    $MonitorTimer.Add_Tick({
        $mItem = $null
        while ($Global:MonitorQueue.TryDequeue([ref]$mItem)) {
            if ($mItem.Type -eq "Stats") {
                foreach ($Stat in $mItem.Data) {
                    if ($Global:DriveUIMap.ContainsKey($Stat.DriveLetter)) {
                        $Global:DriveUIMap[$Stat.DriveLetter].Health.Text = $Stat.Health
                        $Global:DriveUIMap[$Stat.DriveLetter].Temp.Text   = $Stat.Temp
                    }
                }
            }
        }
        Request-AsyncDriveStats -Queue $Global:MonitorQueue
    })
    $MonitorTimer.Start()

    # Trigger first diagnostic query immediately
    Request-AsyncDriveStats -Queue $Global:MonitorQueue
})

# Async Execution Worker
$BtnStart.Add_Click({
    if ($BtnStart.Content -eq "Finished") {
        $Window.Close()
        return
    }

    $SelectedTasks = @{
        DoTemp = $ChkTempFiles.IsChecked; DoRecycle = $ChkRecycleBin.IsChecked
        DoCleanmgr = $ChkCleanmgr.IsChecked; DoFlushDNS = $ChkFlushDNS.IsChecked; DoDism = $ChkDism.IsChecked
    }

    if (($SelectedTasks.Values | Where-Object { $_ -eq $true }).Count -eq 0) {
        $TxtStatus.Text = "Please select at least one task to run."; return
    }

    $BtnStart.IsEnabled = $false; $BtnStart.Content = "Cleaning..."
    $BtnStart.Background = $BrushActiveBG; $BtnStart.Foreground = $BrushActiveFG
    $CleanProgress.Value = 0; $TxtProgressPercent.Text = "0%"
    $InteractiveControls | ForEach-Object { $_.IsEnabled = $false }

    $Global:LogQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
    $Global:ProgressQueue = [System.Collections.Concurrent.ConcurrentQueue[hashtable]]::new()
    $Global:FinishedQueue = [System.Collections.Concurrent.ConcurrentQueue[bool]]::new()

    $ScriptBlock = {
        param($CurrentDir, $RegFiles, $SelectedTasks, $LogQueue, $ProgressQueue, $FinishedQueue)

        function Send-Log ($msg) { if (-not [string]::IsNullOrWhiteSpace($msg)) { $LogQueue.Enqueue($msg) } }
        function Send-Progress ($val, $status) { $ProgressQueue.Enqueue(@{ Value = $val; Status = $status }) }

        function Invoke-SilentProcess ($FileName, $Arguments) {
            try {
                $pinfo = New-Object System.Diagnostics.ProcessStartInfo -Property @{
                    FileName = $FileName; Arguments = $Arguments; UseShellExecute = $false
                    RedirectStandardOutput = $true; RedirectStandardError = $true; CreateNoWindow = $true
                }
                $p = [System.Diagnostics.Process]::Start($pinfo)
                while (-not $p.StandardOutput.EndOfStream) {
                    $line = $p.StandardOutput.ReadLine()
                    if ($line) { Send-Log $line.Trim() }
                }
                $p.WaitForExit(); $p.Close()
            } catch { Send-Log "Task ($FileName) finished." }
        }

        $TotalTasks = ($SelectedTasks.Values | Where-Object { $_ -eq $true }).Count
        $CompletedTasks = 0

        foreach ($File in $RegFiles) {
            $FilePath = Join-Path $CurrentDir $File
            if (Test-Path $FilePath) { Invoke-SilentProcess "reg.exe" "import `"$FilePath`"" }
        }

        if ($SelectedTasks.DoTemp) {
            Send-Progress ([Math]::Round(($CompletedTasks / $TotalTasks) * 100)) "Clearing temporary files..."
            Send-Log "=== CLEARING TEMP FILES AND LOGS ==="
            @("C:\Windows\Temp\*", "C:\Windows\Prefetch\*", "C:\Windows\SoftwareDistribution\Download\*", "$([System.IO.Path]::GetTempPath())*", "C:\Intel", "C:\PerfLogs") | ForEach-Object {
                if (Test-Path $_) { Send-Log "Deleting files in: $_"; Remove-Item $_ -Recurse -Force -ErrorAction SilentlyContinue }
            }
            $CompletedTasks++; Send-Progress ([Math]::Round(($CompletedTasks / $TotalTasks) * 100)) "Temp files cleared."
        }

        if ($SelectedTasks.DoRecycle) {
            Send-Progress ([Math]::Round(($CompletedTasks / $TotalTasks) * 100)) "Emptying Recycle Bin..."
            Send-Log "=== EMPTYING RECYCLE BIN ==="
            Clear-RecycleBin -Force -ErrorAction SilentlyContinue
            Send-Log "Recycle bin emptied."
            $CompletedTasks++; Send-Progress ([Math]::Round(($CompletedTasks / $TotalTasks) * 100)) "Recycle bin emptied."
        }

        # 3. Disk Cleanup Utility
        if ($SelectedTasks.DoCleanmgr) {
            $StartPercent = [Math]::Round(($CompletedTasks / $TotalTasks) * 100)
            Send-Progress $StartPercent "Running Disk Cleanup Utility..."
            Send-Log "=== RUNNING CLEANMGR UTILITY ==="

            # Direct Registry Enforcer: Ensures cleanmgr is flagged to purge Previous Installations (Windows.old)
            $VolCaches = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
            $OldWinKey = Join-Path $VolCaches "Previous Installations"
            if (Test-Path $OldWinKey) {
                Set-ItemProperty -Path $OldWinKey -Name "StateFlags0001" -Value 2 -Type DWord -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $OldWinKey -Name "StateFlags0002" -Value 2 -Type DWord -ErrorAction SilentlyContinue
            }

            $CleanParam = if (Test-Path "C:\Windows.old") { "/SAGERUN:1" } else { "/SAGERUN:2" }
            Invoke-SilentProcess "cleanmgr.exe" $CleanParam
            $CompletedTasks++
            $EndPercent = [Math]::Round(($CompletedTasks / $TotalTasks) * 100)
            Send-Progress $EndPercent "Disk cleanup complete."
        }

        if ($SelectedTasks.DoFlushDNS) {
            Send-Progress ([Math]::Round(($CompletedTasks / $TotalTasks) * 100)) "Flushing DNS Cache..."
            Send-Log "=== FLUSHING DNS CACHE ==="
            Invoke-SilentProcess "ipconfig.exe" "/flushdns"
            $CompletedTasks++; Send-Progress ([Math]::Round(($CompletedTasks / $TotalTasks) * 100)) "DNS Cache flushed."
        }

        if ($SelectedTasks.DoDism) {
            Send-Progress ([Math]::Round(($CompletedTasks / $TotalTasks) * 100)) "Optimizing DISM Component Store..."
            Send-Log "=== RUNNING DISM COMPONENT STORE CLEANUP ==="
            Invoke-SilentProcess "Dism.exe" "/online /Cleanup-Image /StartComponentCleanup /ResetBase /NoRestart /English"
            $CompletedTasks++; Send-Progress ([Math]::Round(($CompletedTasks / $TotalTasks) * 100)) "DISM cleanup complete."
        }

        Send-Progress 100 "Optimization Complete!"
        $FinishedQueue.Enqueue($true)
    }

    $Global:Runspace = [runspacefactory]::CreateRunspace()
    $Global:Runspace.Open()
    $Global:PowerShell = [powershell]::Create()
    $Global:PowerShell.Runspace = $Global:Runspace
    [void]$Global:PowerShell.AddScript($ScriptBlock)
    @($CurrentDir, $Global:RegFiles, $SelectedTasks, $Global:LogQueue, $Global:ProgressQueue, $Global:FinishedQueue) | ForEach-Object {
        [void]$Global:PowerShell.AddArgument($_)
    }
    
    $Global:AsyncResult = $Global:PowerShell.BeginInvoke()

    $Timer = New-Object System.Windows.Threading.DispatcherTimer
    $Timer.Interval = [TimeSpan]::FromMilliseconds(50)
    $Timer.Add_Tick({
        $msg = ""; while ($Global:LogQueue.TryDequeue([ref]$msg)) { Write-GuiLog $msg }
        $prog = $null; while ($Global:ProgressQueue.TryDequeue([ref]$prog)) {
            $CleanProgress.Value = $prog.Value; $TxtProgressPercent.Text = "$($prog.Value)%"; $TxtStatus.Text = $prog.Status
        }

        $isDone = $false
        if ($Global:FinishedQueue.TryDequeue([ref]$isDone) -or ($Global:AsyncResult -and $Global:AsyncResult.IsCompleted)) {
            while ($Global:LogQueue.TryDequeue([ref]$msg)) { Write-GuiLog $msg }
            while ($Global:ProgressQueue.TryDequeue([ref]$prog)) {
                $CleanProgress.Value = $prog.Value; $TxtProgressPercent.Text = "$($prog.Value)%"; $TxtStatus.Text = $prog.Status
            }

            $this.Stop()
            try { $Global:PowerShell.Dispose(); $Global:Runspace.Dispose() } catch {}

            $DriveC = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.Name -eq "C:\" }
            $EndFreeSpace = $DriveC.AvailableFreeSpace
            $SpaceSavedBytes = $EndFreeSpace - $Global:StartingFreeSpace
            $ReadableSpace = if ($SpaceSavedBytes -le 0) { "0 MB" } elseif ($SpaceSavedBytes -gt 1GB) { "$([Math]::Round($SpaceSavedBytes / 1GB, 2)) GB" } else { "$([Math]::Round($SpaceSavedBytes / 1MB, 2)) MB" }

            $TxtReclaimed.Text = $ReadableSpace
            $BtnStart.IsEnabled = $true
            $BtnStart.Content = "Finished"
            $BtnStart.Background = $BrushFinishBG
            $BtnStart.Foreground = $BrushFinishFG
            $InteractiveControls | ForEach-Object { $_.IsEnabled = $true }
            
            Write-GuiLog "=== CLEANUP COMPLETE! TOTAL STORAGE RECLAIMED: $ReadableSpace ==="
            Save-LogAndMaintainHistory
        }
    })
    $Timer.Start()
})

$Window.ShowDialog() | Out-Null