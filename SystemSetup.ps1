if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $currentProcess = [System.Diagnostics.Process]::GetCurrentProcess()
    $currentExecutable = $currentProcess.MainModule.FileName
    if ($currentExecutable -like '*.exe' -and $currentExecutable -notlike '*powershell*') {
        Start-Process -FilePath $currentExecutable -Verb RunAs
    } else {
        $scriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Definition }
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$scriptPath`"")
    }
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$FolderName = "SystemCleanUp"
$CurrentDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
$SourcePath = Join-Path $CurrentDir $FolderName
$TargetPath = Join-Path $env:ProgramFiles $FolderName
$AppName = "Myles Mattlock System CleanUp"
$ExeName = "System CleanUp.exe"
$ProcessName = "System CleanUp"
$UninstallKey = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\SystemCleanUp"
$sourceRoot = [System.IO.Path]::GetFullPath($SourcePath).TrimEnd('\')

if (-not (Test-Path $SourcePath)) {
    [System.Windows.Forms.MessageBox]::Show("The bundled application files were not found next to Setup.exe.", $AppName, 'OK', 'Error')
    exit 1
}

$form = New-Object Windows.Forms.Form
$form.Text = "$AppName Setup"
$form.Size = New-Object Drawing.Size(610, 390)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false

$title = New-Object Windows.Forms.Label
$title.Text = "Install $AppName"
$title.Font = New-Object Drawing.Font('Segoe UI', 16, [Drawing.FontStyle]::Bold)
$title.Location = New-Object Drawing.Point(28, 24)
$title.AutoSize = $true
$form.Controls.Add($title)

$description = New-Object Windows.Forms.Label
$description.Text = "Choose where the application should be installed. Windows will add it to the installed apps list."
$description.Location = New-Object Drawing.Point(30, 65)
$description.Size = New-Object Drawing.Size(535, 40)
$form.Controls.Add($description)

$pathLabel = New-Object Windows.Forms.Label
$pathLabel.Text = 'Install location:'
$pathLabel.Location = New-Object Drawing.Point(30, 125)
$pathLabel.AutoSize = $true
$form.Controls.Add($pathLabel)

$pathBox = New-Object Windows.Forms.TextBox
$pathBox.Text = $TargetPath
$pathBox.Location = New-Object Drawing.Point(30, 150)
$pathBox.Size = New-Object Drawing.Size(430, 25)
$form.Controls.Add($pathBox)

$browse = New-Object Windows.Forms.Button
$browse.Text = 'Browse...'
$browse.Location = New-Object Drawing.Point(470, 149)
$browse.Size = New-Object Drawing.Size(90, 27)
$browse.Add_Click({
    $dialog = New-Object Windows.Forms.FolderBrowserDialog
    $dialog.SelectedPath = $pathBox.Text
    if ($dialog.ShowDialog() -eq 'OK') { $pathBox.Text = Join-Path $dialog.SelectedPath $FolderName }
})
$form.Controls.Add($browse)

$desktop = New-Object Windows.Forms.CheckBox
$desktop.Text = 'Create a desktop shortcut'
$desktop.Checked = $true
$desktop.Location = New-Object Drawing.Point(30, 205)
$desktop.AutoSize = $true
$form.Controls.Add($desktop)

$startMenu = New-Object Windows.Forms.CheckBox
$startMenu.Text = 'Create a Start Menu shortcut'
$startMenu.Checked = $true
$startMenu.Location = New-Object Drawing.Point(30, 235)
$startMenu.AutoSize = $true
$form.Controls.Add($startMenu)

$status = New-Object Windows.Forms.Label
$status.Location = New-Object Drawing.Point(30, 275)
$status.Size = New-Object Drawing.Size(535, 25)
$form.Controls.Add($status)

$install = New-Object Windows.Forms.Button
$install.Text = 'Install'
$install.Location = New-Object Drawing.Point(390, 310)
$install.Size = New-Object Drawing.Size(100, 30)
$install.DialogResult = [Windows.Forms.DialogResult]::None
$form.AcceptButton = $install
$form.Controls.Add($install)

$cancel = New-Object Windows.Forms.Button
$cancel.Text = 'Cancel'
$cancel.Location = New-Object Drawing.Point(500, 310)
$cancel.Size = New-Object Drawing.Size(80, 30)
$cancel.Add_Click({ $form.Close() })
$form.CancelButton = $cancel
$form.Controls.Add($cancel)

$install.Add_Click({
    $install.Enabled = $false
    $browse.Enabled = $false
    $cancel.Enabled = $false
    try {
        $target = $pathBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($target)) { throw 'Choose an installation folder.' }
        $status.Text = 'Closing any running instance...'
        Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path $target)) { New-Item -ItemType Directory -Path $target -Force | Out-Null }
        $status.Text = 'Copying application files...'
        $targetRoot = [System.IO.Path]::GetFullPath($target).TrimEnd('\')
        if ($sourceRoot -ne $targetRoot) {
            Get-ChildItem -LiteralPath $SourcePath -Force |
                Where-Object { $_.Name -notin @('.DS_Store', '__MACOSX') } |
                Copy-Item -Destination $target -Recurse -Force -ErrorAction Stop
            Get-ChildItem $target -Recurse -Force | Where-Object { $_.Name -ne '.DS_Store' } | Unblock-File -ErrorAction SilentlyContinue
        }
        $executablePath = Join-Path $target $ExeName
        $shell = New-Object -ComObject WScript.Shell
        $createShortcut = {
            param($shortcutPath)
            $shortcut = $shell.CreateShortcut($shortcutPath)
            $shortcut.TargetPath = $executablePath
            $shortcut.WorkingDirectory = $target
            $shortcut.Description = 'Clean up Windows using Myles Mattlock System CleanUp'
            $shortcut.Save()
        }
        if ($desktop.Checked) { & $createShortcut (Join-Path ([Environment]::GetFolderPath('Desktop')) "$AppName.lnk") }
        if ($startMenu.Checked) {
            $menu = Join-Path ([Environment]::GetFolderPath('CommonPrograms')) $AppName
            New-Item -ItemType Directory -Path $menu -Force | Out-Null
            & $createShortcut (Join-Path $menu "$AppName.lnk")
        }
        New-Item $UninstallKey -Force | Out-Null
        New-ItemProperty $UninstallKey -Name DisplayName -Value $AppName -PropertyType String -Force | Out-Null
        New-ItemProperty $UninstallKey -Name DisplayVersion -Value '3.0.0' -PropertyType String -Force | Out-Null
        New-ItemProperty $UninstallKey -Name Publisher -Value 'Myles Mattlock' -PropertyType String -Force | Out-Null
        New-ItemProperty $UninstallKey -Name InstallLocation -Value $target -PropertyType String -Force | Out-Null
        $uninstallCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command `"Remove-Item -LiteralPath '$target' -Recurse -Force`""
        New-ItemProperty $UninstallKey -Name UninstallString -Value $uninstallCommand -PropertyType String -Force | Out-Null
        $status.Text = 'Installation complete.'
        [Windows.Forms.MessageBox]::Show('System CleanUp was installed successfully.', "$AppName Setup", 'OK', 'Information')
        $form.Close()
    } catch {
        $status.Text = 'Installation failed.'
        [Windows.Forms.MessageBox]::Show($_.Exception.Message, "$AppName Setup", 'OK', 'Error')
        $install.Enabled = $true
        $browse.Enabled = $true
        $cancel.Enabled = $true
    }
})

[void]$form.ShowDialog()