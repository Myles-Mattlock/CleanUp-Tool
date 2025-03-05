Write-Output "Setting wallpaper, this won't show till system has restarted"
## CustomSetup
##Copying wallpaper####################################################
# Define paths
$sourcePath = "D:\powershell\Evolved-Ideas-Background.png"
$destinationFolder = "$Env:USERPROFILE\Pictures"
$destinationPath = "$destinationFolder\Evolved-Ideas-Background.png"

# Create destination folder if it doesn't exist
if (-Not (Test-Path -Path $destinationFolder)) {
    New-Item -ItemType Directory -Path $destinationFolder
}

# Copy the file
Copy-Item -Path $sourcePath -Destination $destinationPath

#######################################################################

##Setting wallpaper####################################################
$WallpaperPath = "$Env:USERPROFILE\Pictures\Evolved-Ideas-Background.png"
$RegPath = "HKCU:\Control Panel\Desktop"
Set-ItemProperty -Path $RegPath -Name Wallpaper -Value $WallpaperPath
rundll32.exe user32.dll, UpdatePerUserSystemParameters

#######################################################################

Write-Output "Setting Dark theme, explorer.exe will restart"
Start-Sleep -Seconds 10
Set-ItemProperty -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize -Name AppsUseLightTheme -Value 0
Set-ItemProperty -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize -Name SystemUsesLightTheme -Value 0

#########################Setting END TASK #############################

$path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings"
      $name = "TaskbarEndTask"
      $value = 1

      # Ensure the registry key exists
      if (-not (Test-Path $path)) {
        New-Item -Path $path -Force | Out-Null
      }

      # Set the property, creating it if it doesn't exist
      New-ItemProperty -Path $path -Name $name -PropertyType DWord -Value $value -Force | Out-Null

#######################################################################

##setting NEW right click menu
Remove-Item -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" -Recurse -Confirm:$false -Force
# Restarting Explorer in the Undo Script might not be necessary, as the Registry change without restarting Explorer does work, but just to make sure.
Write-Host Restarting explorer.exe ...
$process = Get-Process -Name "explorer"
Stop-Process -InputObject $process

##Uncomment lines below for old right click menu
# New-Item -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" -Name "InprocServer32" -force -value ""
# Write-Host Restarting explorer.exe ...
# $process = Get-Process -Name "explorer"
# Stop-Process -InputObject $process


##Update
winget update --all --silent

## Removal
winget remove "Copilot"
winget remove "3D Viewer"
winget remove "Cortana" 
winget remove "Feedback Hub" 
winget remove "Microsoft 365 (Office)"
winget remove "Films & TV" 
winget remove "maps" 
winget remove "Mail and Calendar" 
winget remove "Paint 3D" 
winget remove "skype" 
winget remove "Microsoft News"
winget remove "Microsoft To Do"
winget remove "Microsoft Bing Search"
winget remove "Power Automate"
winget remove "Quick assist"
winget remove "Solitaire & Casual Games"
winget remove "Sound Recorder"
winget remove "Sticky Notes"
winget remove "Weather"
winget remove "Xbox"
winget remove "Xbox Live"
winget remove "Microsoft Clipchamp"
winget remove "MSN Weather"


Get-AppxPackage -allusers Microsoft.XboxGamingOverlay | Remove-AppxPackage
Get-AppxPackage -allusers Microsoft.XboxApp | Remove-AppxPackage
Get-AppxPackage -allusers XboxOneSmartGlass | Remove-AppxPackage
Get-AppxPackage -allusers Microsoft.XboxSpeechToTextOverlay | Remove-AppxPackage
Get-AppxPackage -allusers Microsoft.XboxIdentityProvider | Remove-AppxPackage

## Required packages
#installing onedrive
Write-Host "Installing OneDrive"
Start-Process -FilePath winget -ArgumentList "install -e --accept-source-agreements --accept-package-agreements --silent Microsoft.OneDrive " -NoNewWindow -Wait

winget install Microsoft.Teams Google.Chrome Jabra.Direct Adobe.Acrobat.Reader.64-bit xanderfrangos.twinkletray --silent


## USB Dell Dock driver
winget install DisplayLink.GraphicsDriver 

## Install for devs
winget install Microsoft.VisualStudioCode Microsoft.VisualStudio.2022.Community Postman.Postman Docker.DockerDesktop Oracle.MySQLWorkbench Git.Git Notepad++.Notepad++ OpenJS.NodeJS --silent

## Enable WSL
wsl --update

## cleaning up
Write-Output "Cleaning up system"
#cleanmgr.exe /d C: /VERYLOWDISK
Dism.exe /online /Cleanup-Image /StartComponentCleanup /ResetBase

##REBOOT
Write-Output "Computer will Restart in 30 Seconds, please save work and close apps!!"

$total = 30
$count = $total
 
while ($count -gt 0) {
 
  "$count seconds remaining..."
  Start-Sleep -Seconds 1
  $count--
 
}
 
"Countdown finished!"

Write-Output "Computer will Restart Now!!"
Start-Sleep -Seconds 5
restart-computer

