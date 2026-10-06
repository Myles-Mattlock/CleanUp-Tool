# Myles Mattlock System CleanUp

System CleanUp is a Windows PowerShell/WPF utility for selecting and running common system cleanup tasks. It can clear temporary files and logs, empty the Recycle Bin, run Disk Cleanup, flush DNS, and run DISM component-store cleanup. The GUI also provides cleanup profiles, drive information, progress reporting, and cleanup logs.

The application requires administrator privileges because several cleanup operations modify protected Windows locations and settings.

## Repository Layout

- `CleanUp.ps1` - main cleanup application source.
- `SystemSetup.ps1` - graphical installer source.
- `SystemCleanUp/` - registry settings and image assets packaged with the application.
- `elevate.manifest.xml` - requests administrator privileges for compiled executables.
- `.github/workflows/build-app.yaml` - CI build and release workflow.

## Requirements

Build on Windows with:

- Windows PowerShell 5.1 or PowerShell 7.
- The PS2EXE PowerShell module.
- Windows SDK, for `mt.exe` and manifest embedding.

Install PS2EXE for the current user:

```powershell
Install-Module -Name ps2exe -Scope CurrentUser -Force
```

Install the Windows SDK from Microsoft's Windows SDK download page if `mt.exe` is not installed.

## Run From Source

To run the main application directly:

```powershell
Set-Location C:\git\CleanUp-Tool
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CleanUp.ps1
```

The application self-elevates with UAC when needed. The main script uses the registry files and image assets relative to its own directory, so keep the repository layout intact.

When a newer non-prerelease GitHub release is available, the application asks whether to update. Accepting downloads the `SystemCleanUp.zip` release asset, extracts it, replaces the installed application after the current process exits, and starts the updated executable. The automatic updater requires the packaged executable layout and the release asset to be named `SystemCleanUp.zip`.

To test the installer source directly:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\SystemSetup.ps1
```

The installer copies the packaged application files to `C:\Program Files\SystemCleanUp` by default. It can also create desktop and Start Menu shortcuts, register the application with Windows, and remove those entries during uninstall.

## Build Locally

Run these commands from the repository root in PowerShell:

```powershell
$ErrorActionPreference = 'Stop'

Remove-Item .\Staging_System -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path .\Staging_System\SystemCleanUp -Force | Out-Null

ps2exe -InputFile .\CleanUp.ps1 `
	   -OutputFile '.\Staging_System\SystemCleanUp\System CleanUp.exe' `
	   -IconFile .\icon.ico `
	   -title 'System CleanUp' `
	   -description 'Windows system cleanup utility' `
	   -company 'Myles Mattlock' `
	   -product 'Myles Mattlock System CleanUp' `
	   -version '3.0.1'

ps2exe -InputFile .\SystemSetup.ps1 `
	   -OutputFile '.\Staging_System\Setup.exe' `
	   -IconFile .\icon.ico `
	   -title 'System CleanUp Setup' `
	   -description 'Myles Mattlock System CleanUp installer' `
	   -company 'Myles Mattlock' `
	   -product 'Myles Mattlock System CleanUp' `
	   -version '3.0.1'

Copy-Item .\SystemCleanUp\*.reg, .\SystemCleanUp\*.jpg `
		  -Destination .\Staging_System\SystemCleanUp\

ps2exe -InputFile .\SystemCleanUp\Update.ps1 `
		  -OutputFile '.\Staging_System\SystemCleanUp\Update.exe' `
		  -title 'System CleanUp Updater' `
		  -description 'System CleanUp update helper' `
		  -company 'Myles Mattlock' `
		  -product 'Myles Mattlock System CleanUp' `
		  -version '3.0.1'
```

Find the Windows SDK manifest tool and embed the administrator manifest in both executables:

```powershell
$mtPath = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\*\bin\*\x64\mt.exe' `
	-Recurse | Select-Object -First 1 -ExpandProperty FullName

& $mtPath -manifest .\elevate.manifest.xml `
	-outputresource:'.\Staging_System\SystemCleanUp\System CleanUp.exe;#1'

& $mtPath -manifest .\elevate.manifest.xml `
	-outputresource:'.\Staging_System\Setup.exe;#1'
```

Create the distributable archive:

```powershell
Compress-Archive -Path .\Staging_System\* -DestinationPath .\SystemCleanUp.zip -Force
```

The final staging layout is:

```text
Staging_System\
  Setup.exe
  SystemCleanUp\
	System CleanUp.exe
	DiskCleanupSettings.reg
	DiskCleanupSettings2.reg
	Logo.jpg
	LogoRight.jpg
	Update.exe
```

Run `Setup.exe` from this layout or from the ZIP after extracting it. Do not remove the `SystemCleanUp` subfolder beside `Setup.exe`; the installer uses it as its source payload.

## CI Build

The GitHub Actions workflow performs the same build, embeds the administrator manifests, creates `SystemCleanUp.zip`, and uploads it as a release artifact. It runs for pushes to `dev` and `main`, version tags, and manual workflow dispatches.

## Signing

The executables include Myles Mattlock as file metadata, but they are not digitally signed by this repository. Consequently, Windows may show `Unknown Publisher` in the UAC prompt. A trusted Authenticode certificate is required for a verified publisher name. Sign both executables after manifest embedding and before creating the ZIP.

## Uninstall

The installer registers System CleanUp in the standard Windows uninstall registry location. Uninstalling from Settings or `appwiz.cpl` removes the installed files, desktop shortcut, Start Menu shortcut, and uninstall registration.

## Safety

Cleanup operations can delete temporary files, modify Disk Cleanup settings, empty the Recycle Bin, and run DISM with `/ResetBase`. Review the selected tasks before starting cleanup and keep backups of important data.