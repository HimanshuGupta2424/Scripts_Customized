# ====================================================================
# Forcepoint VPN Client + ECA Uninstall Script
# Purpose: Stops Forcepoint services, terminates related processes,
#          and silently uninstalls Forcepoint VPN Client and ECA.

# ====================================================================

# --- Configuration ---
$vpnProductCode = "{BD2B344B-C6B9-4E58-85F9-AB3E0BFC67F4}"
$ecaProductCode = "{0A36DB64-3CD9-4C22-867D-490C51CFEDCB}"
$eca2ProductCode = "{9203A9FD-3CA1-488C-9B55-A3734F6FCA74}"

$vpnLog = "C:\Windows\Logs\Uninstall_FPVPNClient.log"
$ecaLog = "C:\Windows\Logs\Uninstall_FPECA.log"
$transcriptLog = "C:\Windows\Logs\Forcepoint_Cleanup_Phase1.log"

$serviceNames = @("sgipsecvpn","sgvpn","sgfw","sglog","sglogsrv","sgipsec","fpvpn","fppsvc","fpcpl","fpcmon","fpeca","fpdiag","fpwfp","fpfilter")

$processNames = @("sggui","sgvpn","fppsvc","fpeca","fpdiag","fpvpn","fpcpl","fpcmon","wepsvc","sgfw","sglog","sglogsrv","sgipsec","sgipsecvpn")

# --- Start Transcript Logging ---
Start-Transcript -Path $transcriptLog -Append

# --- Stop and Delete Services ---
foreach ($svcName in $serviceNames) {
    try {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($svc) {
            Write-Output "Stopping service: $svcName"
            Set-Service -Name $svcName -StartupType Disabled -ErrorAction SilentlyContinue

            Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue

            Start-Process -FilePath "sc.exe" -ArgumentList "delete $svcName" -WindowStyle Hidden -Wait
        } else {
            Write-Output "Service not found: $svcName"
        }
    } catch {
        Write-Output "Error stopping service $svcName : $($_.Exception.Message)"
    }
}

# --- Kill Processes ---
foreach ($procName in $processNames) {
    try {
        $proc = Get-Process -Name $procName -ErrorAction SilentlyContinue
        if ($proc) {
            Write-Output "Terminating process: $procName"
            Stop-Process -Name $procName -Force -ErrorAction SilentlyContinue
        } else {
            Write-Output "Process not running: $procName"
        }
    } catch {
        Write-Output "Error terminating process $procName : $($_.Exception.Message)"
    }
}

# --- Uninstall Forcepoint VPN Client ---
try {
    Write-Output "Uninstalling Forcepoint VPN Client..."
    $vpnArgs = "/X $vpnProductCode /qn /l*v `"$vpnLog`""
    $vpnProc = Start-Process -FilePath "msiexec.exe" -ArgumentList $vpnArgs -Wait -PassThru

    if ($vpnProc.ExitCode -eq 0) {
        Write-Output "VPN uninstall completed successfully."
    }
    elseif ($vpnProc.ExitCode -eq 1605) {
        Write-Output "VPN uninstall skipped — product not installed (1605)."
    }
    else {
        Write-Output "VPN uninstall returned exit code: $($vpnProc.ExitCode)"
    }
}
catch {
    Write-Output "VPN uninstall failed: $_"
}

# --- Uninstall Forcepoint ECA ---
try {
    Write-Output "Uninstalling Forcepoint Endpoint Context Agent..."
    $ecaArgs = "/X $ecaProductCode REBOOT=ReallySuppress /qn /l*v `"$ecaLog`""
    $ecaProc = Start-Process -FilePath "msiexec.exe" -ArgumentList $ecaArgs -Wait -PassThru

    if ($ecaProc.ExitCode -eq 0) {
        Write-Output "ECA uninstall completed successfully."
    }
    elseif ($ecaProc.ExitCode -eq 1605) {
        Write-Output "ECA uninstall skipped — product not installed (1605)."
    }
    else {
        Write-Output "ECA uninstall returned exit code: $($ecaProc.ExitCode)"
    }
}
catch {
    Write-Output "ECA uninstall failed: $($_.Exception.Message)"
}

# --- Uninstall Forcepoint ECA 2 ---
try {
    Write-Output "Uninstalling Forcepoint Endpoint Context Agent 2..."
    $eca2Args = "/X $eca2ProductCode REBOOT=ReallySuppress /qn /l*v `"$ecaLog`""
    $eca2Proc = Start-Process -FilePath "msiexec.exe" -ArgumentList $eca2Args -Wait -PassThru

    if ($eca2Proc.ExitCode -eq 0) {
        Write-Output "ECA2 uninstall completed successfully."
    }
    elseif ($eca2Proc.ExitCode -eq 1605) {
        Write-Output "ECA2 uninstall skipped — product not installed (1605)."
    }
    else {
        Write-Output "ECA2 uninstall returned exit code: $($eca2Proc.ExitCode)"
    }
}
catch {
    Write-Output "ECA2 uninstall failed: $($_.Exception.Message)"
}


# --- Registry Cleanup ---
$regDeleteCmds = @(
    'reg delete "HKLM\SYSTEM\CurrentControlSet\Services\fpeca" /f',
    'reg delete "HKLM\SYSTEM\CurrentControlSet\Services\FPDIAG" /f',
    'reg delete "HKLM\SYSTEM\CurrentControlSet\Services\FpECAWfp" /f',
    'reg delete "HKLM\SYSTEM\CurrentControlSet\Services\FpFile" /f',
    'reg delete "HKLM\SYSTEM\CurrentControlSet\Services\Fppsvc" /f',
    'reg delete "HKLM\SYSTEM\CurrentControlSet\Services\FpProcess" /f',
    'reg delete "HKLM\SOFTWARE\Forcepoint" /f',
    'reg delete "HKLM\SOFTWARE\WOW6432Node\Forcepoint" /f',
    'reg delete "HKLM\SOFTWARE\Websense" /f',
    'reg delete "HKLM\SOFTWARE\WOW6432Node\Websense" /f',
    'reg delete "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{BD23B4A9-CB94-4E58-9F59-A3E9E5C6F9F4}" /f',
    'reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{0A36DB64-3CD9-4C22-867D-490C51CFEDCB}" /f',
    'reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{9203A9FD-3CA1-488C-9B55-A3734F6FCA74}" /f',
    'reg delete "HKEY_CLASSES_ROOT\Installer\Products\B443B2DB9B6C85E4589FBAE3B0CF764F" /f',
    'reg delete "HKEY_CLASSES_ROOT\Installer\Products\46BD63A09DC322C468D794C015FCDEBC" /f'
)

foreach ($cmd in $regDeleteCmds) {
    Write-Output "Running: $cmd"
    try {
        $output = & cmd.exe /c $cmd 2>&1
        $exit = $LASTEXITCODE
        if ($output) { Write-Output "reg output: $output" }
        Write-Output "reg exit code: $exit"
    } catch {
        Write-Output "Exception running reg delete: $($_.Exception.Message)"
    }
}

# --- Copy Phase 2 Script ---
Copy-Item "Forcepoint_Cleanup_Phase2.ps1" "C:\Temp" -Force

# --- Create Scheduled Task for Post-Reboot Cleanup ---
$taskName = "ForcepointPostRebootCleanup"
$scriptPath = "C:\Temp\Forcepoint_Cleanup_Phase2.ps1"
$Action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -File `"$scriptPath`""
$Trigger = New-ScheduledTaskTrigger -AtStartup
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
Register-ScheduledTask -TaskName $taskName -Action $Action -Trigger $Trigger -Principal $Principal -Force

Write-Output "Scheduled Task '$taskName' created. Phase 2 will run on next reboot.."

# --- Stop Transcript ---
Stop-Transcript