# --- 1. Administrator Check (Self-Elevating) ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $ExePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    if ($ExePath -like "*.exe" -and $ExePath -notlike "*powershell*") { Start-Process -FilePath $ExePath -Verb RunAs }
    else { Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$($PSCommandPath ?? $MyInvocation.MyCommand.Definition)`"" -Verb RunAs }
    Exit
}

Clear-Host
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Write-Host "`n Starting Myles Mattlock CleanUp Tool GUI...`n" -ForegroundColor DarkCyan

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# --- CONFIGURATION ---
$Global:CurrentVersion = "3.0.0" 
$Global:RepoName = "Myles-Mattlock/CleanUp-Tool"
$Global:RegFiles = @("DiskCleanupSettings.reg", "DiskCleanupSettings2.reg") 
$Global:LogDir = "C:\Program Files\SystemCleanUp\Logs"
$CurrentDir = if ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName -like "*.exe" -and [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName -notlike "*powershell*") {
    [System.IO.Path]::GetDirectoryName([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
} else { $PSCommandPath ? (Split-Path -Parent $PSCommandPath) : (Get-Location) }

# --- XAML UI DESIGN ---
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Myles Mattlock CleanUp Tool" Height="800" Width="960" 
        WindowStartupLocation="CenterScreen" Background="#1E1E1E" Foreground="#FFFFFF" ResizeMode="CanMinimize">
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <Border Grid.Row="0" Background="#252526" CornerRadius="8" Padding="15" Margin="0,0,0,15">
            <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <Image x:Name="ImgLogo" Grid.Column="0" Width="64" Height="64" Margin="0,0,15,0" Stretch="Uniform"/>
                <StackPanel Grid.Column="1" VerticalAlignment="Center">
                    <TextBlock Text="Myles Mattlock System CleanUp" FontSize="22" FontWeight="Bold"/>
                    <TextBlock Text="Optimize storage, system files, and component health" FontSize="13" Foreground="#AAAAAA"/>
                </StackPanel>
                <TextBlock x:Name="TxtVersion" Grid.Column="2" Text="v3.0.0" VerticalAlignment="Center" Foreground="#888888" FontSize="15" Margin="0,0,15,0"/>
                <Image x:Name="ImgLogoRight" Grid.Column="3" Width="64" Height="64" Stretch="Uniform"/>
            </Grid>
        </Border>

        <!-- Top Stats Bar -->
        <UniformGrid Grid.Row="1" Columns="3" Margin="0,0,0,15">
            <Border Background="#2D2D30" CornerRadius="6" Padding="12" Margin="0,0,5,0">
                <StackPanel>
                    <TextBlock Text="INITIAL FREE" FontSize="11" FontWeight="Bold" Foreground="#888888"/>
                    <TextBlock x:Name="TxtInitialSpace" Text="Calculating..." FontSize="16" FontWeight="Bold" Margin="0,4,0,0"/>
                </StackPanel>
            </Border>
            <Border Background="#2D2D30" CornerRadius="6" Padding="12" Margin="5,0,5,0">
                <StackPanel>
                    <TextBlock Text="DRIVE HEALTH" FontSize="11" FontWeight="Bold" Foreground="#888888"/>
                    <TextBlock x:Name="TxtDriveHealth" Text="Checking..." FontSize="16" FontWeight="Bold" Foreground="#00E5FF" Margin="0,4,0,0"/>
                </StackPanel>
            </Border>
            <Border Background="#2D2D30" CornerRadius="6" Padding="12" Margin="5,0,0,0">
                <StackPanel>
                    <TextBlock Text="TEMP" FontSize="11" FontWeight="Bold" Foreground="#888888"/>
                    <TextBlock x:Name="TxtDriveTemp" Text="-- °C" FontSize="16" FontWeight="Bold" Foreground="#FFCC00" Margin="0,4,0,0"/>
                </StackPanel>
            </Border>
        </UniformGrid>

        <!-- Tasks & Profiles -->
        <Border Grid.Row="2" Background="#252526" CornerRadius="6" Padding="12" Margin="0,0,0,15">
            <StackPanel>
                <Grid Margin="0,0,0,10">
                    <TextBlock Text="SELECT TASKS TO RUN" FontSize="11" FontWeight="Bold" Foreground="#888888" VerticalAlignment="Center"/>
                    <StackPanel HorizontalAlignment="Right" Orientation="Horizontal">
                        <TextBlock Text="PROFILES:" FontSize="11" FontWeight="Bold" Foreground="#888888" VerticalAlignment="Center" Margin="0,0,10,0"/>
                        <Button x:Name="BtnProfileDefault" Content="Default" Width="75" Height="24" Background="#007ACC" Foreground="White" Margin="0,0,5,0" Cursor="Hand"/>
                        <Button x:Name="BtnProfileServer" Content="Server" Width="75" Height="24" Background="#2D2D30" Foreground="#AAAAAA" Margin="0,0,5,0" Cursor="Hand"/>
                        <Button x:Name="BtnProfileCustom" Content="Custom" Width="75" Height="24" Background="#2D2D30" Foreground="#AAAAAA" Cursor="Hand"/>
                    </StackPanel>
                </Grid>
                <WrapPanel>
                    <CheckBox x:Name="ChkTempFiles" Content="Clear Temp Files &amp; System Logs" IsChecked="True" Foreground="#FFF" Margin="0,0,15,5"/>
                    <CheckBox x:Name="ChkRecycleBin" Content="Empty Recycle Bin" IsChecked="True" Foreground="#FFF" Margin="0,0,15,5"/>
                    <CheckBox x:Name="ChkCleanmgr" Content="Run Disk Cleanup" IsChecked="True" Foreground="#FFF" Margin="0,0,15,5"/>
                    <CheckBox x:Name="ChkFlushDNS" Content="Flush DNS Cache" IsChecked="True" Foreground="#FFF" Margin="0,0,15,5"/>
                    <CheckBox x:Name="ChkDism" Content="DISM Cleanup" IsChecked="True" Foreground="#FFF" Margin="0,0,15,5"/>
                </WrapPanel>
            </StackPanel>
        </Border>

        <!-- Terminal Output -->
        <Border Grid.Row="3" Background="#0C0C0C" BorderBrush="#333333" BorderThickness="1" CornerRadius="6" Padding="10">
            <ScrollViewer x:Name="LogScroll" VerticalScrollBarVisibility="Auto">
                <TextBox x:Name="TxtLog" Background="Transparent" Foreground="#00FF66" BorderThickness="0" FontFamily="Consolas" FontSize="12" IsReadOnly="True" TextWrapping="Wrap"/>
            </ScrollViewer>
        </Border>

        <!-- Storage Reclaimed -->
        <Border Grid.Row="4" Background="#2D2D30" CornerRadius="6" Padding="12" Margin="0,10,0,0">
            <Grid>
                <StackPanel>
                    <TextBlock Text="TOTAL STORAGE RECLAIMED" FontSize="11" FontWeight="Bold" Foreground="#888888"/>
                    <TextBlock Text="Space freed during current session" FontSize="11" Foreground="#AAAAAA"/>
                </StackPanel>
                <TextBlock x:Name="TxtReclaimed" Text="0 MB" FontSize="20" FontWeight="Bold" Foreground="#00FF66" HorizontalAlignment="Right" VerticalAlignment="Center"/>
            </Grid>
        </Border>

        <!-- Progress -->
        <Grid Grid.Row="5" Height="16" Margin="0,10,0,10">
            <ProgressBar x:Name="CleanProgress" Foreground="#007ACC" Background="#2D2D30" BorderThickness="0"/>
            <TextBlock x:Name="TxtProgressPercent" Text="0%" Foreground="#FFFFFF" FontSize="10" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Grid>

        <!-- Actions -->
        <Grid Grid.Row="6">
            <TextBlock x:Name="TxtStatus" Text="Ready to start cleanup." VerticalAlignment="Center" Foreground="#AAAAAA" FontSize="13"/>
            <Button x:Name="BtnStart" Content="Start Cleanup" Width="140" Height="36" HorizontalAlignment="Right" Background="#007ACC" Foreground="White" FontWeight="Bold" Cursor="Hand"/>
        </Grid>
    </Grid>
</Window>
"@

# Load XAML
$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$Window = [Windows.Markup.XamlReader]::Load($reader)

# Map Elements dynamically
@("ImgLogo", "ImgLogoRight", "TxtVersion", "TxtInitialSpace", "TxtReclaimed", "TxtDriveHealth", "TxtDriveTemp", 
  "TxtLog", "LogScroll", "CleanProgress", "TxtProgressPercent", "TxtStatus", "BtnStart",
  "BtnProfileDefault", "BtnProfileServer", "BtnProfileCustom",
  "ChkTempFiles", "ChkRecycleBin", "ChkCleanmgr", "ChkFlushDNS", "ChkDism") | ForEach-Object {
    Set-Variable -Name $_ -Value $Window.FindName($_)
}

$TaskCheckboxes = @($ChkTempFiles, $ChkRecycleBin, $ChkCleanmgr, $ChkFlushDNS, $ChkDism)
$InteractiveControls = $TaskCheckboxes + @($BtnProfileDefault, $BtnProfileServer, $BtnProfileCustom)

function Write-GuiLog ($Message) {
    if ([string]::IsNullOrWhiteSpace($Message)) { return }
    $TxtLog.AppendText("[$((Get-Date).ToString('HH:mm:ss'))] $Message`n")
    $LogScroll.ScrollToEnd()
}

function Set-Profile ($Profile) {
    if (-not $BtnStart.IsEnabled) { return }
    $bActive = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#007ACC")
    $bInactive = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#2D2D30")
    
    $BtnProfileDefault.Background = if ($Profile -eq "Default") { $bActive } else { $bInactive }
    $BtnProfileServer.Background  = if ($Profile -eq "Server")  { $bActive } else { $bInactive }
    $BtnProfileCustom.Background  = if ($Profile -eq "Custom")  { $bActive } else { $bInactive }

    if ($Profile -in @("Default", "Server")) {
        $ChkTempFiles.IsChecked  = $true
        $ChkRecycleBin.IsChecked = $true
        $ChkCleanmgr.IsChecked   = $true
        $ChkFlushDNS.IsChecked   = ($Profile -eq "Default")
        $ChkDism.IsChecked       = ($Profile -eq "Default")
    }
}

# Attach Checkbox / Profile Events
$BtnProfileDefault.Add_Click({ Set-Profile "Default" })
$BtnProfileServer.Add_Click({ Set-Profile "Server" })
$BtnProfileCustom.Add_Click({ Set-Profile "Custom" })

$TaskCheckboxes | ForEach-Object {
    $_.Add_Click({ Set-Profile "Custom" })
}

# --- DIAGNOSTICS & UPDATES ---
function Get-DriveHealthDiagnostics {
    Write-GuiLog "=== DISK HEALTH & SMART DIAGNOSTICS ==="
    try {
        $Disk = Get-CimInstance Win32_DiskDrive | Select-Object -First 1
        Write-GuiLog "Drive [0]: $($Disk.Model) - SMART Status: $($Disk.Status)"
        
        $PhysDisk = Get-PhysicalDisk | Select-Object -First 1 | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
        if ($PhysDisk.Temperature) { $TxtDriveTemp.Text = "$($PhysDisk.Temperature) °C" }
        if ($PhysDisk.Wear -ne $null) { $TxtDriveHealth.Text = "$(100 - $PhysDisk.Wear)% Health" } else { $TxtDriveHealth.Text = "Healthy" }
    } catch { $TxtDriveHealth.Text = "Healthy" }
}

$Window.Add_Loaded({
    @("Logo.jpg", "LogoRight.jpg") | ForEach-Object {
        $imgPath = Join-Path $CurrentDir $_
        if (Test-Path $imgPath) {
            $bmp = New-Object System.Windows.Media.Imaging.BitmapImage (New-Object System.Uri($imgPath))
            if ($_ -eq "Logo.jpg") { $ImgLogo.Source = $bmp } else { $ImgLogoRight.Source = $bmp }
        }
    }

    $TxtVersion.Text = "v$Global:CurrentVersion"
    $Global:StartingFreeSpace = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace
    $TxtInitialSpace.Text = "$([Math]::Round($Global:StartingFreeSpace / 1GB, 2)) GB"
    
    Write-GuiLog "System Cleanup Initialized."
    Get-DriveHealthDiagnostics
})

# --- ASYNCHRONOUS RUNSPACE WORKER ---
$BtnStart.Add_Click({
    $SelectedTasks = @{
        DoTemp = $ChkTempFiles.IsChecked; DoRecycle = $ChkRecycleBin.IsChecked
        DoCleanmgr = $ChkCleanmgr.IsChecked; DoFlushDNS = $ChkFlushDNS.IsChecked; DoDism = $ChkDism.IsChecked
    }

    if (($SelectedTasks.Values | Where-Object { $_ }).Count -eq 0) {
        $TxtStatus.Text = "Please select at least one task to run."; return
    }

    $BtnStart.IsEnabled = $false
    $BtnStart.Content = "Cleaning..."
    $InteractiveControls | ForEach-Object { $_.IsEnabled = $false }

    $Global:LogQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
    $Global:ProgressQueue = [System.Collections.Concurrent.ConcurrentQueue[hashtable]]::new()
    $Global:FinishedQueue = [System.Collections.Concurrent.ConcurrentQueue[bool]]::new()

    $ScriptBlock = {
        param($CurrentDir, $RegFiles, $SelectedTasks, $LogQueue, $ProgressQueue, $FinishedQueue)
        function Log ($m) { $LogQueue.Enqueue($m) }
        function Progress ($v, $s) { $ProgressQueue.Enqueue(@{ Value = $v; Status = $s }) }
        function Run-Silent ($exe, $arg) { Start-Process $exe -ArgumentList $arg -NoNewWindow -Wait -ErrorAction SilentlyContinue }

        $Total = ($SelectedTasks.Values | Where-Object { $_ }).Count
        $Done = 0

        foreach ($File in $RegFiles) {
            $FilePath = Join-Path $CurrentDir $File
            if (Test-Path $FilePath) { Run-Silent "reg.exe" "import `"$FilePath`"" }
        }

        if ($SelectedTasks.DoTemp) {
            Progress ([Math]::Round(($Done / $Total) * 100)) "Clearing temp files..."
            Log "=== CLEARING TEMP FILES ==="
            @("C:\Windows\Temp\*", "C:\Windows\Prefetch\*", "C:\Windows\SoftwareDistribution\Download\*", "$([System.IO.Path]::GetTempPath())*") | ForEach-Object {
                if (Test-Path $_) { Remove-Item $_ -Recurse -Force -ErrorAction SilentlyContinue }
            }
            $Done++; Progress ([Math]::Round(($Done / $Total) * 100)) "Temp files cleared."
        }

        if ($SelectedTasks.DoRecycle) {
            Progress ([Math]::Round(($Done / $Total) * 100)) "Emptying Recycle Bin..."
            Log "=== EMPTYING RECYCLE BIN ==="
            Clear-RecycleBin -Force -ErrorAction SilentlyContinue
            $Done++; Progress ([Math]::Round(($Done / $Total) * 100)) "Recycle bin emptied."
        }

        if ($SelectedTasks.DoCleanmgr) {
            Progress ([Math]::Round(($Done / $Total) * 100)) "Running Disk Cleanup..."
            Log "=== RUNNING CLEANMGR ==="
            Run-Silent "cleanmgr.exe" "/sagerun:1"
            $Done++; Progress ([Math]::Round(($Done / $Total) * 100)) "Disk cleanup complete."
        }

        if ($SelectedTasks.DoFlushDNS) {
            Progress ([Math]::Round(($Done / $Total) * 100)) "Flushing DNS..."
            Log "=== FLUSHING DNS CACHE ==="
            Run-Silent "ipconfig.exe" "/flushdns"
            $Done++; Progress ([Math]::Round(($Done / $Total) * 100)) "DNS Cache flushed."
        }

        if ($SelectedTasks.DoDism) {
            Progress ([Math]::Round(($Done / $Total) * 100)) "Optimizing DISM..."
            Log "=== RUNNING DISM CLEANUP ==="
            Run-Silent "Dism.exe" "/online /Cleanup-Image /StartComponentCleanup /ResetBase /NoRestart /English"
            $Done++; Progress ([Math]::Round(($Done / $Total) * 100)) "DISM cleanup complete."
        }

        Progress 100 "Optimization Complete!"
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
            $CleanProgress.Value = $prog.Value
            $TxtProgressPercent.Text = "$($prog.Value)%"
            $TxtStatus.Text = $prog.Status
        }

        $isDone = $false
        if ($Global:FinishedQueue.TryDequeue([ref]$isDone) -or ($Global:AsyncResult -and $Global:AsyncResult.IsCompleted)) {
            $this.Stop()
            try { $Global:PowerShell.Dispose(); $Global:Runspace.Dispose() } catch {}

            $SpaceSaved = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace - $Global:StartingFreeSpace
            $ReadableSpace = if ($SpaceSaved -le 0) { "0 MB" } elseif ($SpaceSaved -gt 1GB) { "$([Math]::Round($SpaceSaved / 1GB, 2)) GB" } else { "$([Math]::Round($SpaceSaved / 1MB, 2)) MB" }

            $TxtReclaimed.Text = $ReadableSpace
            $BtnStart.IsEnabled = $true
            $BtnStart.Content = "Finished"
            $InteractiveControls | ForEach-Object { $_.IsEnabled = $true }
            
            Write-GuiLog "=== CLEANUP COMPLETE! TOTAL STORAGE RECLAIMED: $ReadableSpace ==="
        }
    })
    $Timer.Start()
})

$Window.ShowDialog() | Out-Null