Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
# --- 1. Launch without a visible PowerShell console ---
$HostProcessName = [System.Diagnostics.Process]::GetCurrentProcess().ProcessName
if ($HostProcessName -match "^(powershell|pwsh)$" -and $env:CLEANUP_TOOL_HIDDEN -ne "1") {
    $env:CLEANUP_TOOL_HIDDEN = "1"
    $ScriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Definition }
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
    Exit
}

# Hide the console window created by a console-based EXE conversion.
if ($HostProcessName -notmatch "^(powershell|pwsh)$") {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class CleanupConsole {
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr handle, int command);
}
"@
    $ConsoleHandle = [CleanupConsole]::GetConsoleWindow()
    if ($ConsoleHandle -ne [IntPtr]::Zero) {
        [CleanupConsole]::ShowWindow($ConsoleHandle, 0) | Out-Null
    }
}

# --- 2. Administrator Check (Self-Elevating) ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $ExePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    if ($ExePath -like "*.exe" -and $ExePath -notlike "*powershell*") {
        Start-Process -FilePath $ExePath -Verb RunAs -WindowStyle Hidden
    } else {
        $ScriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Definition }
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`"" -Verb RunAs -WindowStyle Hidden
    }
    Exit
}

# --- CONFIGURATION ---
$Global:CurrentVersion = "3.1.0"
$Global:RepoName = "Myles-Mattlock/CleanUp-Tool"
$Global:UpdatePromptShown = $false
$Global:RegFiles = @("DiskCleanupSettings.reg", "DiskCleanupSettings2.reg") 
$Global:LogDir = "C:\Program Files\SystemCleanUp\Logs"
$Global:WindowSettingsPath = Join-Path $env:LOCALAPPDATA "SystemCleanUp\window-settings.json"

if ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName -like "*.exe" -and [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName -notlike "*powershell*") {
    $CurrentDir = [System.IO.Path]::GetDirectoryName([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
} elseif ($PSCommandPath) {
    $CurrentDir = Split-Path -Parent $PSCommandPath
} else {
    $CurrentDir = Get-Location
}

# Color Constants
$HexGreen = "#4ADE80"
$HexAmber = "#FACC15"
$HexRed   = "#F87171"
$HexWhite = "#FFFFFF"
$HexMuted = "#888888"

function Start-SelfUpdate {
    param([string]$DownloadUrl, [string]$TargetDirectory, [string]$ApplicationPath, [int]$ParentProcessId)
    $updaterPath = Join-Path $TargetDirectory 'Update.exe'
    if ([string]::IsNullOrWhiteSpace($DownloadUrl)) {
        [System.Windows.Forms.MessageBox]::Show('The update package URL was empty. Download the latest release manually.', 'System CleanUp', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }
    if (-not (Test-Path -LiteralPath $updaterPath -PathType Leaf)) {
        [System.Windows.Forms.MessageBox]::Show("The update helper was not found:`n$updaterPath`n`nReinstall the latest package.", 'System CleanUp', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }
    try {
        $arguments = @(
            "-DownloadUrl `"$DownloadUrl`""
            "-TargetDirectory `"$TargetDirectory`""
            "-ApplicationPath `"$ApplicationPath`""
            "-ParentProcessId $ParentProcessId"
        ) -join ' '
        $process = Start-Process -FilePath $updaterPath -ArgumentList $arguments -WindowStyle Normal -PassThru -ErrorAction Stop
        Write-GuiLog "Updater started (PID $($process.Id))."
        $Window.Close()
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Could not start the update helper:`n$($_.Exception.Message)`n`nPath: $updaterPath", 'System CleanUp', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
}

# --- XAML UI DESIGN ---
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Myles Mattlock System CleanUp" Height="920" Width="1000" 
        WindowStartupLocation="CenterScreen" Background="#1E1E1E" Foreground="#FFFFFF"
        ResizeMode="CanResize" MinWidth="700" MinHeight="780">
    <Window.Resources>
        <!-- Custom Shimmer Progress Bar Style -->
        <Style x:Key="ShimmerProgressBarStyle" TargetType="ProgressBar">
            <Setter Property="Background" Value="#2D2D30"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ProgressBar">
                        <Grid x:Name="TemplateRoot">
                            <Border Background="{TemplateBinding Background}" CornerRadius="4"/>
                            <Track x:Name="PART_Track">
                                <Track.DecreaseRepeatButton>
                                    <RepeatButton Command="Slider.DecreaseLarge">
                                        <RepeatButton.Template>
                                            <ControlTemplate>
                                                <Border x:Name="FillBorder" CornerRadius="4">
                                                    <Border.Background>
                                                        <LinearGradientBrush x:Name="ShimmerBrush" StartPoint="0,0" EndPoint="1,0">
                                                            <GradientStop Color="#007ACC" Offset="0.0"/>
                                                            <GradientStop Color="#660098FF" Offset="0.4"/>
                                                            <GradientStop Color="#FFFFFF" Offset="0.5"/>
                                                            <GradientStop Color="#660098FF" Offset="0.6"/>
                                                            <GradientStop Color="#007ACC" Offset="1.0"/>
                                                        </LinearGradientBrush>
                                                    </Border.Background>
                                                </Border>
                                            </ControlTemplate>
                                        </RepeatButton.Template>
                                    </RepeatButton>
                                </Track.DecreaseRepeatButton>
                                <Track.IncreaseRepeatButton>
                                    <RepeatButton Command="Slider.IncreaseLarge">
                                        <RepeatButton.Template>
                                            <ControlTemplate>
                                                <Border Background="Transparent"/>
                                            </ControlTemplate>
                                        </RepeatButton.Template>
                                    </RepeatButton>
                                </Track.IncreaseRepeatButton>
                            </Track>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="Windows11CheckBoxStyle" TargetType="CheckBox">
            <Setter Property="Foreground" Value="#F3F3F3"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Padding" Value="7,0,0,0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="CheckBox">
                        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                            <Border x:Name="Box"
                                    Width="17" Height="17"
                                    Background="#292929"
                                    BorderBrush="#777777"
                                    BorderThickness="1"
                                    CornerRadius="4"
                                    VerticalAlignment="Center">
                                <Path x:Name="CheckMark"
                                      Data="M 3,8.5 L 6.5,12 L 14,4.5"
                                      Stroke="#FFFFFF"
                                      StrokeThickness="2"
                                      StrokeStartLineCap="Round"
                                      StrokeEndLineCap="Round"
                                      Visibility="Collapsed"/>
                            </Border>
                            <ContentPresenter Margin="{TemplateBinding Padding}"
                                              VerticalAlignment="Center"
                                              RecognizesAccessKey="True"/>
                        </StackPanel>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Box" Property="Background" Value="#333333"/>
                                <Setter TargetName="Box" Property="BorderBrush" Value="#AAAAAA"/>
                            </Trigger>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="Box" Property="Background" Value="#0078D4"/>
                                <Setter TargetName="Box" Property="BorderBrush" Value="#0078D4"/>
                                <Setter TargetName="CheckMark" Property="Visibility" Value="Visible"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="Box" Property="Opacity" Value="0.5"/>
                                <Setter Property="Foreground" Value="#777777"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

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

        <Style x:Key="CancelButtonStyle" TargetType="Button">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" CornerRadius="6">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="StartButtonStyle" TargetType="Button">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}" CornerRadius="6">
                            <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center" Orientation="Horizontal">
                                <!-- Loading Spinner Canvas -->
                                <Viewbox x:Name="SpinnerBox" Width="16" Height="16" Margin="0,0,8,0" Visibility="Collapsed">
                                    <Canvas Width="24" Height="24">
                                        <Path Data="M12,2A10,10 0 1,0 22,12A10,10 0 0,0 12,2Z" Stroke="#44FFFFFF" StrokeThickness="3"/>
                                        <Path Data="M12,2A10,10 0 0,1 22,12" Stroke="#FFFFFF" StrokeThickness="3"/>
                                        <Canvas.RenderTransform>
                                            <RotateTransform x:Name="SpinnerRotate" Angle="0" CenterX="12" CenterY="12"/>
                                        </Canvas.RenderTransform>
                                    </Canvas>
                                </Viewbox>
                                <TextBlock x:Name="BtnText" Text="{TemplateBinding Content}" VerticalAlignment="Center"/>
                            </StackPanel>
                        </Border>
                        <ControlTemplate.Triggers>
                            <MultiTrigger>
                                <MultiTrigger.Conditions>
                                    <Condition Property="IsMouseOver" Value="True"/>
                                    <Condition Property="Tag" Value="Ready"/>
                                </MultiTrigger.Conditions>
                                <Setter TargetName="border" Property="Background" Value="#0098FF"/>
                            </MultiTrigger>
                            <MultiTrigger>
                                <MultiTrigger.Conditions>
                                    <Condition Property="IsMouseOver" Value="True"/>
                                    <Condition Property="Tag" Value="Finished"/>
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
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
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
                <TextBlock x:Name="TxtVersion" Grid.Column="2" Text="v3.1.0" VerticalAlignment="Center" Foreground="#888888" FontSize="16" FontWeight="SemiBold" Margin="0,0,20,0"/>
                <Image x:Name="ImgLogoRight" Grid.Column="3" Width="78.75" Height="78.75" VerticalAlignment="Center" Stretch="Uniform"/>
            </Grid>
        </Border>

        <!-- Top Stats Bar Container for Multiple Drives -->
        <!-- Task Selection Checkboxes & Profile Buttons -->
        <Border Grid.Row="1" Background="#252526" CornerRadius="6" Padding="12" Margin="0,0,0,15">
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
                    <CheckBox x:Name="ChkTempFiles" Content="Clear Temp Files &amp; System Logs" IsChecked="True" Style="{StaticResource Windows11CheckBoxStyle}" Margin="0,0,15,5" Cursor="Hand"/>
                    <CheckBox x:Name="ChkRecycleBin" Content="Empty Recycle Bin" IsChecked="True" Style="{StaticResource Windows11CheckBoxStyle}" Margin="0,0,15,5" Cursor="Hand"/>
                    <CheckBox x:Name="ChkCleanmgr" Content="Run Disk Cleanup Utility" IsChecked="True" Style="{StaticResource Windows11CheckBoxStyle}" Margin="0,0,15,5" Cursor="Hand"/>
                    <CheckBox x:Name="ChkFlushDNS" Content="Flush DNS Cache" IsChecked="True" Style="{StaticResource Windows11CheckBoxStyle}" Margin="0,0,15,5" Cursor="Hand"/>
                    <CheckBox x:Name="ChkDism" Content="DISM Component Store Cleanup" IsChecked="True" Style="{StaticResource Windows11CheckBoxStyle}" Margin="0,0,15,5" Cursor="Hand"/>
                </WrapPanel>
            </StackPanel>
        </Border>

        <!-- Output Log Terminal -->
        <Border Grid.Row="2" Background="#0C0C0C" BorderBrush="#333333" BorderThickness="1" CornerRadius="6" Padding="12" ClipToBounds="True" MinHeight="0">
            <TextBox x:Name="TxtLog" Background="Transparent" Foreground="#00FF66" BorderThickness="0" FontFamily="Consolas" FontSize="13" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" VerticalAlignment="Stretch" MinHeight="0"/>
        </Border>

        <!-- Reclaimed Storage Box -->
        <Border Grid.Row="3" Height="82" MaxHeight="82" Background="#2D2D30" CornerRadius="6" Padding="15" Margin="0,15,0,0">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0" VerticalAlignment="Center">
                    <TextBlock Text="TOTAL STORAGE RECLAIMED" FontSize="11" FontWeight="Bold" Foreground="#888888"/>
                    <TextBlock Text="Space freed during the current optimization session" FontSize="12" Foreground="#AAAAAA" Margin="0,2,0,0"/>
                </StackPanel>
                <TextBlock x:Name="TxtReclaimed" Grid.Column="1" Text="0 MB" MaxWidth="150" TextTrimming="CharacterEllipsis" FontSize="22" FontWeight="Bold" Foreground="#00FF66" VerticalAlignment="Center"/>
            </Grid>
        </Border>

        <!-- Progress Bar with Percentage Overlay -->
        <Grid Grid.Row="4" Height="18" Margin="0,15,0,15">
            <ProgressBar x:Name="CleanProgress" Style="{StaticResource ShimmerProgressBarStyle}" Value="0" Maximum="100"/>
            <TextBlock x:Name="TxtProgressPercent" Text="0%" Foreground="#FFFFFF" FontSize="11" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Grid>

        <!-- Action Controls -->
        <Grid Grid.Row="5">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock x:Name="TxtStatus" Text="Ready to start cleanup." VerticalAlignment="Center" Foreground="#AAAAAA" FontSize="14"/>
            <Button x:Name="BtnCancel" Grid.Column="1" Content="Cancel Cleanup" Width="140" Height="42" Margin="0,0,10,0"
                    Style="{StaticResource CancelButtonStyle}" Background="#555555" Foreground="#000000" FontSize="13" FontWeight="Bold" BorderThickness="0" Cursor="Hand" IsEnabled="False"
                    ToolTip="Cancel is available during cleanup stages." ToolTipService.ShowOnDisabled="True"/>
            <Button x:Name="BtnStart" Grid.Column="2" Content="Start Cleanup" Tag="Ready" Width="160" Height="42" 
                    Style="{StaticResource StartButtonStyle}" Background="#007ACC" Foreground="White" FontSize="14" FontWeight="Bold" BorderThickness="0" Cursor="Hand"/>
        </Grid>
    </Grid>
</Window>
"@

# Load XAML & Map UI Controls
$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$Window = [Windows.Markup.XamlReader]::Load($reader)

@("ImgLogo", "ImgLogoRight", "TxtVersion", "TxtReclaimed",
    "TxtLog", "CleanProgress", "TxtProgressPercent", "TxtStatus", "BtnCancel", "BtnStart",
  "BtnProfileDefault", "BtnProfileServer", "BtnProfileCustom",
  "ChkTempFiles", "ChkRecycleBin", "ChkCleanmgr", "ChkFlushDNS", "ChkDism") | ForEach-Object {
    Set-Variable -Name $_ -Value $Window.FindName($_)
}
$LogScroll = $TxtLog

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

# --- ANIMATION CONTROLS ---
$Duration = New-Object System.Windows.Duration ([TimeSpan]::FromSeconds(1))
$SpinAnimation = New-Object System.Windows.Media.Animation.DoubleAnimation (0, 360, $Duration)
$SpinAnimation.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever

# Progress Bar Shimmer Brush Sweep Animation
$ShimmerDuration = New-Object System.Windows.Duration ([TimeSpan]::FromSeconds(1.5))
$ShimmerAnimation = New-Object System.Windows.Media.Animation.PointAnimation
$ShimmerAnimation.From = New-Object System.Windows.Point (-1, 0)
$ShimmerAnimation.To = New-Object System.Windows.Point (2, 0)
$ShimmerAnimation.Duration = $ShimmerDuration
$ShimmerAnimation.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever

function Start-ProgressBarShimmer {
    $Template = $CleanProgress.Template
    $Track = $Template.FindName("PART_Track", $CleanProgress)
    if ($Track -and $Track.DecreaseRepeatButton) {
        $DecTemplate = $Track.DecreaseRepeatButton.Template
        $FillBorder = $DecTemplate.FindName("FillBorder", $Track.DecreaseRepeatButton)
        $ShimmerBrush = $DecTemplate.FindName("ShimmerBrush", $Track.DecreaseRepeatButton)
        
        if ($FillBorder -and $ShimmerBrush) {
            $FillBorder.Background = $ShimmerBrush
            $ShimmerBrush.BeginAnimation([System.Windows.Media.LinearGradientBrush]::StartPointProperty, $ShimmerAnimation)
        }
    }
}

function Stop-ProgressBarShimmer {
    $Template = $CleanProgress.Template
    $Track = $Template.FindName("PART_Track", $CleanProgress)
    if ($Track -and $Track.DecreaseRepeatButton) {
        $DecTemplate = $Track.DecreaseRepeatButton.Template
        $FillBorder = $DecTemplate.FindName("FillBorder", $Track.DecreaseRepeatButton)
        $ShimmerBrush = $DecTemplate.FindName("ShimmerBrush", $Track.DecreaseRepeatButton)
        
        if ($ShimmerBrush) {
            $ShimmerBrush.BeginAnimation([System.Windows.Media.LinearGradientBrush]::StartPointProperty, $null)
        }
        if ($FillBorder) {
            $FillBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#007ACC")
        }
    }
}

function Start-ButtonSpinner {
    $Template = $BtnStart.Template
    $SpinnerBox = $Template.FindName("SpinnerBox", $BtnStart)
    $SpinnerRotate = $Template.FindName("SpinnerRotate", $BtnStart)

    if ($SpinnerBox -and $SpinnerRotate) {
        $SpinnerBox.Visibility = [System.Windows.Visibility]::Visible
        $SpinnerRotate.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $SpinAnimation)
    }
}

function Stop-ButtonSpinner {
    $Template = $BtnStart.Template
    $SpinnerBox = $Template.FindName("SpinnerBox", $BtnStart)
    $SpinnerRotate = $Template.FindName("SpinnerRotate", $BtnStart)

    if ($SpinnerBox -and $SpinnerRotate) {
        $SpinnerBox.Visibility = [System.Windows.Visibility]::Collapsed
        $SpinnerRotate.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $null)
    }
}

# --- GLOBAL FUNCTIONS ---
function Write-GuiLog ($Message) {
    if ([string]::IsNullOrWhiteSpace($Message)) { return }
    $TxtLog.AppendText("[$((Get-Date).ToString('HH:mm:ss'))] $Message`n")
    $LogScroll.ScrollToEnd()
}

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

function Restore-WindowSize {
    try {
        if (Test-Path -LiteralPath $Global:WindowSettingsPath -PathType Leaf) {
            $Settings = Get-Content -LiteralPath $Global:WindowSettingsPath -Raw | ConvertFrom-Json
            if ($Settings.Width -ge $Window.MinWidth) { $Window.Width = [double]$Settings.Width }
            if ($Settings.Height -ge $Window.MinHeight) { $Window.Height = [double]$Settings.Height }
        }
    } catch {}
}

function Save-WindowSize {
    try {
        $SettingsDirectory = Split-Path -Parent $Global:WindowSettingsPath
        if (-not (Test-Path -LiteralPath $SettingsDirectory)) {
            New-Item -Path $SettingsDirectory -ItemType Directory -Force | Out-Null
        }
        @{ Width = [Math]::Round($Window.ActualWidth); Height = [Math]::Round($Window.ActualHeight) } |
            ConvertTo-Json | Set-Content -LiteralPath $Global:WindowSettingsPath -Encoding utf8
    } catch {}
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

$Window.Add_Loaded({
    Restore-WindowSize

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
    
    Write-GuiLog "System Cleanup Initialized."

    # GLOBAL INITIALIZATION QUEUE
    $Global:InitQueue = [System.Collections.Concurrent.ConcurrentQueue[hashtable]]::new()

    # ASYNCHRONOUS BACKGROUND STARTUP WORKER
    $InitScript = {
        param($RepoName, $CurrentVersion, $InitQueue)

        # Check Updates
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $Releases = Invoke-RestMethod -Uri "https://api.github.com/repos/$RepoName/releases" -Method Get -UserAgent "Mozilla/5.0 PowerShell-App" -ErrorAction Stop
            $LocalVersion = [version]($CurrentVersion.ToLower().TrimStart('v').Split("-")[0])
            $HasUpdate = $false
            foreach ($Rel in ($Releases | Where-Object { $_.prerelease -eq $false })) {
                if ([version]($Rel.tag_name.ToLower().TrimStart('v').Split("-")[0]) -gt $LocalVersion) {
                    $Asset = $Rel.assets | Where-Object { $_.name -eq "SystemCleanUp.zip" } | Select-Object -First 1
                    if ($null -ne $Asset -and -not [string]::IsNullOrWhiteSpace($Asset.browser_download_url)) {
                        $InitQueue.Enqueue(@{ Type = "Update"; Msg = "Version $($Rel.tag_name) is available."; Url = $Asset.browser_download_url })
                        $HasUpdate = $true; break
                    }
                    $InitQueue.Enqueue(@{ Type = "Log"; Msg = "Version $($Rel.tag_name) is available, but SystemCleanUp.zip was not found." })
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
            elseif ($item.Type -eq "Update" -and -not $Global:UpdatePromptShown) {
                $Global:UpdatePromptShown = $true
                $choice = [System.Windows.Forms.MessageBox]::Show("$($item.Msg)`n`nDownload and install it now?", "System CleanUp Update", 'YesNo', 'Information')
                if ($choice -eq [System.Windows.Forms.DialogResult]::Yes) {
                    $applicationPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
                    Start-SelfUpdate -DownloadUrl $item.Url -TargetDirectory $CurrentDir -ApplicationPath $applicationPath -ParentProcessId ([System.Diagnostics.Process]::GetCurrentProcess().Id)
                }
            }
        }
        if ($InitAsync.IsCompleted) {
            $this.Stop()
            try { $InitPS.Dispose(); $InitRunspace.Dispose() } catch {}
        }
    })
    $InitTimer.Start()

})

$Window.Add_Closing({ Save-WindowSize })

$BtnCancel.Add_Click({
    if ($Global:CancelQueue) {
        $Global:CancelQueue.Enqueue($true)
        $BtnCancel.IsEnabled = $false
        $BtnCancel.Content = "Stopping..."
        $TxtStatus.Text = "Finishing the current stage safely..."
    }
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

    $BtnStart.IsEnabled = $false
    $BtnStart.Content = "Cleaning..."
    $BtnStart.Tag = "Cleaning"
    $BtnStart.Background = $BrushActiveBG
    $BtnStart.Foreground = $BrushActiveFG
    $BtnCancel.IsEnabled = $true
    $BtnCancel.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#A83232")
    $BtnCancel.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#000000")
    $BtnCancel.Content = "Cancel Cleanup"
    $BtnCancel.ToolTip = "Cancel is available during cleanup stages."
    
    # Start Animations (Spinner & Linear Gradient Progress Bar Sweep)
    Start-ButtonSpinner
    Start-ProgressBarShimmer
    $CleanProgress.Value = 0
    $TxtProgressPercent.Text = "0%"
    $InteractiveControls | ForEach-Object { $_.IsEnabled = $false }

    $Global:LogQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
    $Global:ProgressQueue = [System.Collections.Concurrent.ConcurrentQueue[hashtable]]::new()
    $Global:FinishedQueue = [System.Collections.Concurrent.ConcurrentQueue[bool]]::new()
    $Global:CancelQueue = [System.Collections.Concurrent.ConcurrentQueue[bool]]::new()

    $ScriptBlock = {
        param($CurrentDir, $RegFiles, $SelectedTasks, $LogQueue, $ProgressQueue, $FinishedQueue, $CancelQueue)

        function Send-Log ($msg) { if (-not [string]::IsNullOrWhiteSpace($msg)) { $LogQueue.Enqueue($msg) } }
        function Send-Progress ($val, $status) { $ProgressQueue.Enqueue(@{ Value = $val; Status = $status }) }
        function Stop-Requested { $requested = $false; $item = $false; while ($CancelQueue.TryDequeue([ref]$item)) { $requested = $true }; return $requested }

        function Invoke-SilentProcess ($FileName, $Arguments) {
            $p = $null
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
                $p.WaitForExit()
            } catch { Send-Log "Task ($FileName) finished." }
            finally {
                if ($null -ne $p) { $p.Close(); $p.Dispose() }
            }
        }

        $TotalTasks = ($SelectedTasks.Values | Where-Object { $_ -eq $true }).Count
        $CompletedTasks = 0

        foreach ($File in $RegFiles) {
            $FilePath = Join-Path $CurrentDir $File
            if (Test-Path $FilePath) { Invoke-SilentProcess "reg.exe" "import `"$FilePath`"" }
        }
        if (Stop-Requested) { Send-Log "Cleanup cancelled after the current stage."; Send-Progress 100 "Cleanup cancelled safely."; $FinishedQueue.Enqueue($true); return }

        if ($SelectedTasks.DoTemp) {
            Send-Progress ([Math]::Round(($CompletedTasks / $TotalTasks) * 100)) "Clearing temporary files..."
            Send-Log "=== CLEARING TEMP FILES AND LOGS ==="
            @("C:\Windows\Temp\*", "C:\Windows\Prefetch\*", "C:\Windows\SoftwareDistribution\Download\*", "$([System.IO.Path]::GetTempPath())*", "C:\Intel", "C:\PerfLogs") | ForEach-Object {
                if (Test-Path $_) { Send-Log "Deleting files in: $_"; Remove-Item $_ -Recurse -Force -ErrorAction SilentlyContinue }
            }
            $CompletedTasks++; Send-Progress ([Math]::Round(($CompletedTasks / $TotalTasks) * 100)) "Temp files cleared."
            if (Stop-Requested) { Send-Log "Cleanup cancelled after the current stage."; Send-Progress 100 "Cleanup cancelled safely."; $FinishedQueue.Enqueue($true); return }
        }

        if ($SelectedTasks.DoRecycle) {
            Send-Progress ([Math]::Round(($CompletedTasks / $TotalTasks) * 100)) "Emptying Recycle Bin..."
            Send-Log "=== EMPTYING RECYCLE BIN ==="
            Clear-RecycleBin -Force -ErrorAction SilentlyContinue
            Send-Log "Recycle bin emptied."
            $CompletedTasks++; Send-Progress ([Math]::Round(($CompletedTasks / $TotalTasks) * 100)) "Recycle bin emptied."
            if (Stop-Requested) { Send-Log "Cleanup cancelled after the current stage."; Send-Progress 100 "Cleanup cancelled safely."; $FinishedQueue.Enqueue($true); return }
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
            if (Stop-Requested) { Send-Log "Cleanup cancelled after the current stage."; Send-Progress 100 "Cleanup cancelled safely."; $FinishedQueue.Enqueue($true); return }
        }

        if ($SelectedTasks.DoFlushDNS) {
            Send-Progress ([Math]::Round(($CompletedTasks / $TotalTasks) * 100)) "Flushing DNS Cache..."
            Send-Log "=== FLUSHING DNS CACHE ==="
            Invoke-SilentProcess "ipconfig.exe" "/flushdns"
            $CompletedTasks++; Send-Progress ([Math]::Round(($CompletedTasks / $TotalTasks) * 100)) "DNS Cache flushed."
            if (Stop-Requested) { Send-Log "Cleanup cancelled after the current stage."; Send-Progress 100 "Cleanup cancelled safely."; $FinishedQueue.Enqueue($true); return }
        }

        if ($SelectedTasks.DoDism) {
            Send-Progress ([Math]::Round(($CompletedTasks / $TotalTasks) * 100)) "Optimizing DISM Component Store..."
            Send-Log "=== RUNNING DISM COMPONENT STORE CLEANUP ==="
            Invoke-SilentProcess "Dism.exe" "/online /Cleanup-Image /StartComponentCleanup /ResetBase /NoRestart /English"
            $CompletedTasks++; Send-Progress ([Math]::Round(($CompletedTasks / $TotalTasks) * 100)) "DISM cleanup complete."
            if (Stop-Requested) { Send-Log "Cleanup cancelled after the current stage."; Send-Progress 100 "Cleanup cancelled safely."; $FinishedQueue.Enqueue($true); return }
        }

        Send-Progress 100 "Optimization Complete!"
        $FinishedQueue.Enqueue($true)
    }

    $Global:Runspace = [runspacefactory]::CreateRunspace()
    $Global:Runspace.Open()
    $Global:PowerShell = [powershell]::Create()
    $Global:PowerShell.Runspace = $Global:Runspace
    [void]$Global:PowerShell.AddScript($ScriptBlock)
    @($CurrentDir, $Global:RegFiles, $SelectedTasks, $Global:LogQueue, $Global:ProgressQueue, $Global:FinishedQueue, $Global:CancelQueue) | ForEach-Object {
        [void]$Global:PowerShell.AddArgument($_)
    }
    
    $Global:AsyncResult = $Global:PowerShell.BeginInvoke()

    $Timer = New-Object System.Windows.Threading.DispatcherTimer
    $Timer.Interval = [TimeSpan]::FromMilliseconds(50)
    $Timer.Add_Tick({
        $msg = ""; while ($Global:LogQueue.TryDequeue([ref]$msg)) { Write-GuiLog $msg }
        $prog = $null; while ($Global:ProgressQueue.TryDequeue([ref]$prog)) {
            $CleanProgress.Value = $prog.Value; $TxtProgressPercent.Text = "$($prog.Value)%"; $TxtStatus.Text = $prog.Status
            if ($prog.Status -eq "Optimizing DISM Component Store...") {
                $BtnCancel.IsEnabled = $false
                $BtnCancel.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#555555")
                $BtnCancel.ToolTip = "Cannot stop during DISM cleanup."
            } elseif ($prog.Status -eq "DISM cleanup complete." -and $BtnStart.Content -eq "Cleaning...") {
                $BtnCancel.IsEnabled = $true
                $BtnCancel.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#A83232")
                $BtnCancel.ToolTip = "Cancel is available during cleanup stages."
            }
        }

        $isDone = $false
        if ($Global:FinishedQueue.TryDequeue([ref]$isDone) -or ($Global:AsyncResult -and $Global:AsyncResult.IsCompleted)) {
            while ($Global:LogQueue.TryDequeue([ref]$msg)) { Write-GuiLog $msg }
            while ($Global:ProgressQueue.TryDequeue([ref]$prog)) {
                $CleanProgress.Value = $prog.Value; $TxtProgressPercent.Text = "$($prog.Value)%"; $TxtStatus.Text = $prog.Status
                if ($prog.Status -eq "Optimizing DISM Component Store...") {
                    $BtnCancel.IsEnabled = $false
                    $BtnCancel.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#555555")
                    $BtnCancel.ToolTip = "Cannot stop during DISM cleanup."
                }
            }

            $this.Stop()
            try { $Global:PowerShell.Dispose(); $Global:Runspace.Dispose() } catch {}

            # Stop Animations & Convert Fill to Solid Accent Color
            Stop-ButtonSpinner
            Stop-ProgressBarShimmer
            $CleanProgress.Value = 100

            $DriveC = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.Name -eq "C:\" }
            $EndFreeSpace = $DriveC.AvailableFreeSpace
            $SpaceSavedBytes = $EndFreeSpace - $Global:StartingFreeSpace
            $ReadableSpace = if ($SpaceSavedBytes -le 0) { "0 MB" } elseif ($SpaceSavedBytes -gt 1GB) { "$([Math]::Round($SpaceSavedBytes / 1GB, 2)) GB" } else { "$([Math]::Round($SpaceSavedBytes / 1MB, 2)) MB" }

            $TxtReclaimed.Text = $ReadableSpace
            $BtnStart.IsEnabled = $true
            $BtnStart.Content = "Finished"
            $BtnStart.Tag = "Finished"
            $BtnStart.Background = $BrushFinishBG
            $BtnStart.Foreground = $BrushFinishFG
            $BtnCancel.IsEnabled = $false
            $BtnCancel.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#555555")
            $BtnCancel.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#000000")
            $BtnCancel.Content = "Cancel Cleanup"
            $BtnCancel.ToolTip = "Cancel is available during cleanup stages."
            $InteractiveControls | ForEach-Object { $_.IsEnabled = $true }
            
            Write-GuiLog "=== CLEANUP COMPLETE! TOTAL STORAGE RECLAIMED: $ReadableSpace ==="
            Save-LogAndMaintainHistory
        }
    })
    $Timer.Start()
})

$Window.ShowDialog() | Out-Null
