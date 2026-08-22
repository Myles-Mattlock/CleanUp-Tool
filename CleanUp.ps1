# --- 1. Administrator Check (Self-Elevating) ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $ScriptPath = $MyInvocation.MyCommand.Definition
    if ([string]::IsNullOrEmpty($ScriptPath)) {
        $ScriptPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    }
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`"" -Verb RunAs
    Exit
}

# Add Required WPF & GUI Assemblies
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# --- CONFIGURATION ---
$Global:CurrentVersion = "2.0.1" 
$Global:RepoName = "Myles-Mattlock/CleanUp-Tool"
$Global:RegFiles = @("DiskCleanupSettings.reg", "DiskCleanupSettings2.reg") 
$Global:LogDir = "C:\Program Files\SystemCleanUp\Logs"

$CurrentDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrEmpty($CurrentDir)) { $CurrentDir = Get-Location }

# --- XAML UI DESIGN ---
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Myles Mattlock CleanUp Tool" Height="500" Width="700" 
        WindowStartupLocation="CenterScreen" Background="#1E1E1E" Foreground="#FFFFFF"
        ResizeMode="CanMinimize">
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <Border Grid.Row="0" Background="#252526" CornerRadius="8" Padding="15" Margin="0,0,0,15">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0">
                    <TextBlock Text="System CleanUp Dashboard" FontSize="20" FontWeight="Bold" Foreground="#00E5FF"/>
                    <TextBlock Text="Optimize storage, system files, and component health" FontSize="12" Foreground="#AAAAAA" Margin="0,2,0,0"/>
                </StackPanel>
                <TextBlock x:Name="TxtVersion" Grid.Column="1" Text="v2.0.1" VerticalAlignment="Center" Foreground="#888888" FontSize="14" FontWeight="SemiBold"/>
            </Grid>
        </Border>

        <!-- Stats Bar -->
        <Grid Grid.Row="1" Margin="0,0,0,15">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="10"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <Border Grid.Column="0" Background="#2D2D30" CornerRadius="6" Padding="12">
                <StackPanel>
                    <TextBlock Text="INITIAL FREE SPACE" FontSize="10" FontWeight="Bold" Foreground="#888888"/>
                    <TextBlock x:Name="TxtInitialSpace" Text="Calculating..." FontSize="18" FontWeight="Bold" Foreground="#FFFFFF" Margin="0,4,0,0"/>
                </StackPanel>
            </Border>

            <Border Grid.Column="2" Background="#2D2D30" CornerRadius="6" Padding="12">
                <StackPanel>
                    <TextBlock Text="RECLAIMED STORAGE" FontSize="10" FontWeight="Bold" Foreground="#888888"/>
                    <TextBlock x:Name="TxtReclaimed" Text="0 MB" FontSize="18" FontWeight="Bold" Foreground="#00FF66" Margin="0,4,0,0"/>
                </StackPanel>
            </Border>
        </Grid>

        <!-- Output Log Terminal -->
        <Border Grid.Row="2" Background="#0C0C0C" BorderBrush="#333333" BorderThickness="1" CornerRadius="6" Padding="10">
            <ScrollViewer x:Name="LogScroll" VerticalScrollBarVisibility="Auto">
                <TextBox x:Name="TxtLog" Background="Transparent" Foreground="#00FF66" BorderThickness="0" 
                         FontFamily="Consolas" FontSize="12" IsReadOnly="True" TextWrapping="Wrap"/>
            </ScrollViewer>
        </Border>

        <!-- Progress Bar -->
        <ProgressBar x:Name="CleanProgress" Grid.Row="3" Height="8" Margin="0,15,0,15" Foreground="#00E5FF" Background="#2D2D30" BorderThickness="0" Value="0" Maximum="100"/>

        <!-- Action Controls -->
        <Grid Grid.Row="4">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock x:Name="TxtStatus" Text="Ready to start cleanup." VerticalAlignment="Center" Foreground="#AAAAAA"/>
            <Button x:Name="BtnStart" Grid.Column="1" Content="Start Cleanup" Width="140" Height="36" 
                    Background="#007ACC" Foreground="White" FontWeight="Bold" BorderThickness="0" Cursor="Hand">
                <Button.Resources>
                    <Style TargetType="Border">
                        <Setter Property="CornerRadius" Value="4"/>
                    </Style>
                </Button.Resources>
            </Button>
        </Grid>
    </Grid>
</Window>
"@

# Read XAML
$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$Window = [Windows.Markup.XamlReader]::Load($reader)

# Connect UI Controls to PowerShell Variables
$TxtVersion      = $Window.FindName("TxtVersion")
$TxtInitialSpace = $Window.FindName("TxtInitialSpace")
$TxtReclaimed    = $Window.FindName("TxtReclaimed")
$TxtLog          = $Window.FindName("TxtLog")
$LogScroll       = $Window.FindName("LogScroll")
$CleanProgress   = $Window.FindName("CleanProgress")
$TxtStatus       = $Window.FindName("TxtStatus")
$BtnStart        = $Window.FindName("BtnStart")

# Helper function to write logs safely to UI
function Write-GuiLog ($Message) {
    $TxtLog.Dispatcher.Invoke([Action]{
        $TxtLog.AppendText("[$((Get-Date).ToString('HH:mm:ss'))] $Message`n")
        $LogScroll.ScrollToEnd()
    })
}

# --- INITIALIZATION LOGIC ---
$Window.Add_Loaded({
    $TxtVersion.Text = "v$Global:CurrentVersion"
    $Drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $Global:StartingFreeSpace = $Drive.FreeSpace
    $TxtInitialSpace.Text = "$([Math]::Round($Global:StartingFreeSpace / 1GB, 2)) GB"
    
    Write-GuiLog "System Cleanup Tool Initialized."
    Write-GuiLog "Ready to optimize system storage."
})

# --- CLEANUP TASK RUNNER ---
$BtnStart.Add_Click({
    $BtnStart.IsEnabled = $false
    $BtnStart.Content = "Cleaning..."
    $CleanProgress.Value = 0

    # Run cleanup in a background job so the GUI doesn't freeze
    $ScriptBlock = {
        param($CurrentDir, $RegFiles, $LogDir, $StartingFreeSpace)

        function Dispatch-Progress($Percent, $Status, $LogMsg) {
            [PSCustomObject]@{ Percent = $Percent; Status = $Status; Log = $LogMsg }
        }

        # 1. Importing Registry Configurations
        Dispatch-Progress 10 "Importing registry configurations..." "Importing Registry Configurations..."
        foreach ($File in $RegFiles) {
            $FilePath = Join-Path $CurrentDir $File
            if (Test-Path $FilePath) {
                $proc = Start-Process "reg.exe" -ArgumentList "import `"$FilePath`"" -Wait -PassThru -WindowStyle Hidden
                if ($proc.ExitCode -eq 0) {
                    Dispatch-Progress 15 "Registry set: $File" "  > Applied: $File"
                }
            }
        }

        # 2. Clear Temp Folders
        Dispatch-Progress 30 "Clearing temporary files..." "[1/5] Clearing temporary files and logs..."
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
                Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue
                Dispatch-Progress 40 "Cleaned $Path" "  > Removed: $Path"
            }
        }

        # 3. Empty Recycle Bin
        Dispatch-Progress 55 "Emptying Recycle Bin..." "[2/5] Emptying Recycle Bin..."
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue

        # 4. Cleanmgr Utility
        Dispatch-Progress 70 "Running Disk Cleanup Utility..." "[3/5] Running Cleanmgr..."
        $CleanParam = if (Test-Path "C:\Windows.old") { "/SAGERUN:1" } else { "/SAGERUN:2" }
        Start-Process "cleanmgr.exe" -ArgumentList $CleanParam -Wait

        # 5. Flush DNS
        Dispatch-Progress 85 "Flushing DNS..." "[4/5] Flushing DNS..."
        ipconfig /flushdns | Out-Null

        # 6. DISM Component Store Optimization
        Dispatch-Progress 95 "Optimizing DISM Component Store..." "[5/5] Running DISM Cleanup..."
        Dism.exe /online /Cleanup-Image /StartComponentCleanup /ResetBase /NoRestart | Out-Null

        # Final Calculations
        $DriveEnd = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
        $SpaceSavedBytes = $DriveEnd.FreeSpace - $StartingFreeSpace
        
        $ReadableSpace = if ($SpaceSavedBytes -le 0) {
            "0 MB"
        } elseif ($SpaceSavedBytes -gt 1GB) {
            "$([Math]::Round($SpaceSavedBytes / 1GB, 2)) GB"
        } else {
            "$([Math]::Round($SpaceSavedBytes / 1MB, 2)) MB"
        }

        Dispatch-Progress 100 "Cleanup Complete!" "SUCCESS: Storage Reclaimed: $ReadableSpace"
        return $ReadableSpace
    }

    # Asynchronous Execution with Event Subscriptions
    $powershell = [powershell]::Create().AddScript($ScriptBlock).AddArgument($CurrentDir).AddArgument($Global:RegFiles).AddArgument($Global:LogDir).AddArgument($Global:StartingFreeSpace)
    
    $asyncResult = $powershell.BeginInvoke()
    
    # UI Monitor Timer to update progress asynchronously
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(200)
    $timer.Add_Tick({
        if ($asyncResult.IsCompleted) {
            $timer.Stop()
            $Result = $powershell.EndInvoke($asyncResult)
            $powershell.Dispose()

            $TxtReclaimed.Text = $Result
            $TxtStatus.Text = "Optimization complete!"
            $BtnStart.Content = "Finished"
            $CleanProgress.Value = 100
        }
    })
    $timer.Start()
})

# Launch Modern Window
$Window.ShowDialog() | Out-Null