.\AddWifi.ps1

## Powershell script to setup a clean install

## All commands need to be ran as admin

## Needed to run before:
### Get-ExecutionPolicy -List
### Set-ExecutionPolicy RemoteSigned

## To setup this first in powershell:
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser
Install-Module PSWindowsUpdate -Force  -Scope CurrentUser
Add-WUServiceManager -MicrosoftUpdate  -Scope CurrentUser

## To show/install windows updates
#get-windowsupdate
Install-WindowsUpdate -ForceDownload -ForceInstall -Confirm:$false

.\InstallApplications.ps1