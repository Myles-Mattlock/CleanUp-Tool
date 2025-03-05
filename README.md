To be able to Build you will need the following installed on your system:
ps1exe which can be installed by: Install-Module -Name PowerShellGet -Force -AllowClobber
## https://github.com/MScholtes/PS2EXE
Install-Module -Name PS2EXE -Force -Scope CurrentUser


Then you will need the windows SDK to be able to make the app ask for admin creditals.

When building .exe file you will need to do the following
1. go to the folder that contains CleanUp.ps1, Refresh.ico, elevate.manifest.xml
2. run the following command "ps2exe -InputFile CleanUp.ps1 -OutputFile "System CleanUp.exe" -IconFile Refresh.ico -version "1.0""
3. Then go to CMD and run "C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\mt.exe" -manifest elevate.manifest.xml -outputresource:"SystemCleanUp\Server CleanUp.exe";#1
## if 3. doesn't work you will need to install windows sdk (https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/)