# Check if the script is running as Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output "This program requires administrative privileges. Please run it as Administrator."
    # Pause so the user can see the message before the program exits
    Write-Host "Press Enter to exit..."
    Read-Host
    Exit
}

# Script logic below this point will run with elevated privileges
Write-Output "Running as Administrator! Proceeding with the Cleanup commands..."

# Run the Cleanup commands
try {
        ## Cleaning up
        Add-Type -AssemblyName System.Windows.Forms

    # Display the Yes/No dialog box
    $result = [System.Windows.Forms.MessageBox]::Show(
        "This application will clear your cache and delete files in your recycle bin, continue? (y/n)?",          # Message
        "Confirmation",                     # Title
        [System.Windows.Forms.MessageBoxButtons]::YesNo,  # Buttons
        [System.Windows.Forms.MessageBoxIcon]::Question   # Icon
    )

    # Act based on the user's choice
    if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
        Write-Output "User chose YES"
        # Commands to clear cache and delete files in recycle bin
        Write-Host "Clearing cache"
        Start-Job -ScriptBlock {
            Remove-Item C:\Windows\Temp\* -Recurse -Force
            Remove-Item C:\Windows\Prefetch\* -Recurse -Force
            Remove-Item C:\Windows\SoftwareDistribution\Download\* -Recurse -Force
            $TempPath = [System.IO.Path]::GetTempPath()
            Remove-Item "$TempPath\*" -Recurse -Force
        }
                
        # Importing cleanup settings
        ##reg import "C:\Apps\SystemCleanup\DiskCleanupSettings.reg"
        # Cleaning system
        Write-Output "Cleaning up System"
        Start-Process "cleanmgr.exe" -ArgumentList "/SAGERUN:1"
        Start-Sleep -Seconds 45
    } else {
        Write-Output "User chose NO"
        Write-Host "Operation cancelled." -ForegroundColor Red
            break
    }

} catch {
    Write-Output "An error occurred while running the System Cleanup app"
    Write-Output $_.Exception.Message
}

# Pause to allow the user to review the output
Add-Type -AssemblyName PresentationFramework
[System.Windows.MessageBox]::Show("Any issues please report to myles.mattlock@outlook.com", "User Feedback!")

Write-Output "Application closed"
Start-Sleep -Seconds 3