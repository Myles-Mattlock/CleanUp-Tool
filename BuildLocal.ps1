Install-Module -Name ps2exe -Scope CurrentUser -Force

ps2exe -InputFile .\CleanUp.ps1 `
  -OutputFile '.\CleanUp.exe' `
  -noConsole `
  -STA `
  -requireAdmin `
  -IconFile .\icon.ico `
  -title 'System CleanUp' `
  -description 'Windows system cleanup utility' `
  -company 'Myles Mattlock' `
  -product 'Myles Mattlock System CleanUp' `
  -version '3.0.1'

  ps2exe -InputFile .\Setup.ps1 `
  -OutputFile .\Setup.exe `
  -noConsole `
  -STA `
  -requireAdmin `
  -IconFile .\icon.ico `
  -title 'System CleanUp Setup' `
  -description 'Myles Mattlock System CleanUp installer' `
  -company 'Myles Mattlock' `
  -product 'Myles Mattlock System CleanUp' `
  -version '3.0.1'