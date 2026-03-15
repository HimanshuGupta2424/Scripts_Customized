# ====================================================================
# Forcepoint VPN Client + ECA Uninstall Script
# Purpose: Stops Forcepoint services, terminates related processes,
#          and silently uninstalls Forcepoint VPN Client and ECA.
# ====================================================================

#Part2

$transcriptLog = "C:\Windows\Logs\Forcepoint_Cleanup_Phase2.log"
Start-Transcript -Path $transcriptLog -Append

# --- Folders to Remove ---
$foldersToRemove = @(
    "C:\Program Files\Forcepoint",
    "C:\Program Files (x86)\Forcepoint",
    "C:\Program Files\Websense",
    "C:\ProgramData\Forcepoint"
)

Write-Output "Starting Phase 2 Cleanup..."

# --- File Cleanup ---
foreach ($folder in $foldersToRemove) {
    if (Test-Path $folder) {
        Write-Output "Processing folder: $folder"
        try {
            Write-Output "Taking ownership: $folder"
            $t = Start-Process -FilePath "takeown.exe" -ArgumentList "/f `"$folder`" /r /d y" -NoNewWindow -Wait -PassThru -ErrorAction SilentlyContinue
            Write-Output "takeown exit: $($t.ExitCode)"

            Write-Output "Granting permissions: $folder"
            $i = Start-Process -FilePath "icacls.exe" -ArgumentList "`"$folder`" /grant administrators:F /t /c" -NoNewWindow -Wait -PassThru -ErrorAction SilentlyContinue
            Write-Output "icacls exit: $($i.ExitCode)"

            Remove-Item -Path $folder -Recurse -Force -ErrorAction Stop
            Write-Output "Removed folder: $folder"
        } catch {
            Write-Output "Error removing folder $folder : $($_.Exception.Message)"
        }
    } else {
        Write-Output "Folder not found: $folder"
    }
}

Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{0A36DB64-3CD9-4C22-867D-490C51CFEDCB}" -Force -Recurse
Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{9203A9FD-3CA1-488C-9B55-A3734F6FCA74}" -Force -Recurse

# --- Remove Scheduled Task ---
$taskName = "ForcepointPostRebootCleanup"
try {
    Write-Output "Removing scheduled task: $taskName"
    schtasks.exe /Delete /TN $taskName /F | Out-Null
    Write-Output "Scheduled task removed."
} catch {
    Write-Output "Failed to remove scheduled task: $($_.Exception.Message)"
}

Write-Output "Forcepoint Cleanup Phase 2 Completed."

Stop-Transcript
exit 0
