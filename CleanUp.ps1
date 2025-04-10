# Check if the script is running as Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output "This program requires administrative privileges. Please run it as Administrator."
    # Pause so the user can see the message before the program exits
    Write-Host "Press Enter to exit..."
    Read-Host
    Exit
}

# Script logic below this point will run with elevated privileges
Write-Output "Running as Administrator! Proceeding with the DISM command..."

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
        
        try {
            # Commands to clear cache and delete files in recycle bin
            Write-Host "Clearing cache"
            Remove-Item C:\Windows\Temp\* -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item C:\Windows\Prefetch\* -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item C:\Windows\SoftwareDistribution\Download\* -Recurse -Force -ErrorAction SilentlyContinue
            $TempPath = [System.IO.Path]::GetTempPath()
            Remove-Item "$TempPath\*" -Recurse -Force -ErrorAction SilentlyContinue
            
            Write-Host "Cleaning up system"
        }
        catch {
            $ErrorMessage = "Error occurred on $((Get-Date -Format 'dd-MM-yyyy HH:mm:ss')): $($_.Exception.Message)"
            Add-Content -Path "C:\Logs\SystemCleanUpErrors.log" -Value $ErrorMessage
            # Optionally, you can still provide a silent indication that something went wrong
            # Write-Host "Cleanup encountered some issues (see log file)." -ForegroundColor Yellow
        }

        Write-Host "Cleanup process finished."
        
        # Check if Windows.old exists
        if (Test-Path "C:\Windows.old") {
            # Importing cleanup settings
            Write-Output "Previous Windows installation found. Removing..."
            
            try {
                reg import "C:\Apps\SystemCleanup\DiskCleanupSettings.reg"
                        
                # Remove Windows.old
                Start-Process "cleanmgr.exe" -ArgumentList "/SAGERUN:1" -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 180
            }
            catch {
                $ErrorMessage = "Error occurred on $((Get-Date -Format 'dd-MM-yyyy HH:mm:ss')): $($_.Exception.Message)"
                Add-Content -Path "C:\Logs\SystemCleanUpErrors.log" -Value $ErrorMessage
                # Optionally, you can still provide a silent indication that something went wrong
                # Write-Host "Cleanup encountered some issues (see log file)." -ForegroundColor Yellow
            }
        } else {
            Write-Output "No Previous Windows installation found."
            
            try {
                reg import "C:\Apps\SystemCleanup\DiskCleanupSettings2.reg"
                Start-Process "cleanmgr.exe" -ArgumentList "/SAGERUN:2" -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 90
            }
            catch {
                $ErrorMessage = "Error occurred on $((Get-Date -Format 'dd-MM-yyyy HH:mm:ss')): $($_.Exception.Message)"
                Add-Content -Path "C:\Logs\SystemCleanUpErrors.log" -Value $ErrorMessage
                # Optionally, you can still provide a silent indication that something went wrong
                # Write-Host "Cleanup encountered some issues (see log file)." -ForegroundColor Yellow
            }
        }
        Dism.exe /online /Cleanup-Image /StartComponentCleanup /ResetBase
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
[System.Windows.MessageBox]::Show("Any issues/sugguestions please report to myles.mattlock@outlook.com", "User Feedback!")

Write-Output "Application closed"
Start-Sleep -Seconds 3