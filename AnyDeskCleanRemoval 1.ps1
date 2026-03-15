<#
.SYNOPSIS
    Detects AnyDesk presence and removes it using uninstall entries plus manual cleanup.

.DESCRIPTION
    This script checks for AnyDesk presence via processes, file locations, and uninstall registry entries,
    then invokes the registered uninstall commands and removes common leftover files, folders, and registry traces.
    It also:
      - Optionally creates firewall rules to block AnyDesk.exe inbound and outbound.
      - Optionally deletes AnyDesk.exe from all user Downloads folders.
    It includes logging, admin privilege checks, 64 bit execution enforcement, and error handling.

.NOTES
    File Name      : AnyDeskCleanRemoval.ps1
    Version        : 1.0
    Author         : Wesley.desousa@bureauveritas.com
    Date           : 25/11/2025
    Requirements   : Run as Administrator on Windows 10/11
                     PowerShell 5.0 or higher
                     No third party tools required
    Change log     : 
#>

[CmdletBinding()]
param(
    [switch]$Relaunched
)

# ============================================================================================
# CONSTANTS
# ============================================================================================
[string]$Version       = 'V1.0'
[string]$LogFolder     = "$env:WINDIR\logs"
[string]$LogFile       = "AnyDeskCleanRemoval_$($Version).log"
[string]$LogPath       = Join-Path $LogFolder $LogFile

# Behavior toggles (edit here as needed)
[bool]$SkipFirewall         = $false   # If $true, firewall rules will NOT be created
[bool]$SkipUninstall        = $false   # If $true, uninstall and core cleanup will be skipped
[bool]$SkipDownloadsCleanup = $false   # If $true, Downloads\AnyDesk.exe will NOT be removed

# Build user profiles root from environment
[string]$SystemDriveRoot = $env:SystemDrive
if ([string]::IsNullOrWhiteSpace($SystemDriveRoot)) {
    $SystemDriveRoot = 'C:'
}
[string]$UserProfilesRoot = Join-Path $SystemDriveRoot 'Users'

# Detection constants
[string]$AnyDeskProcessNamePattern = "AnyDesk*"
[string[]]$AnyDeskInstallPaths = @(
    "$env:ProgramFiles\AnyDesk\AnyDesk.exe",
    "$env:ProgramFiles(x86)\AnyDesk\AnyDesk.exe",
    "$env:ProgramData\AnyDesk\AnyDesk.exe",
    "$env:LOCALAPPDATA\AnyDesk\AnyDesk.exe",
    "$env:APPDATA\AnyDesk\AnyDesk.exe"
)

[string[]]$AnyDeskUninstallRoots = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

# ============================================================================================
# INITIALIZE FAILED OPERATIONS ARRAY
# ============================================================================================
$script:failedOperations = New-Object System.Collections.ArrayList

# ============================================================================================
# FUNCTIONS
# ============================================================================================

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )

    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logEntry = "$timestamp [$Level] - $Message"
        $logEntry | Out-File -FilePath $LogPath -Append -Encoding UTF8

        switch ($Level) {
            'Info'    { Write-Host $Message -ForegroundColor Cyan }
            'Warning' { Write-Warning $Message }
            'Error'   { Write-Error $Message }
        }
    }
    catch {
        Write-Warning "Failed to write to log: $_"
    }
}
function Initialize-LogDirectory {
    try {
        if (-not (Test-Path -Path $LogFolder)) {
            New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
            Write-Log "Created log directory: $LogFolder" -Level Info
        }

        if (-not (Test-Path -Path $LogPath)) {
            New-Item -Path $LogPath -ItemType File -Force | Out-Null
            Write-Log "Created log file: $LogPath" -Level Info
        }
    }
    catch {
        throw "Log directory initialization failed: $_"
    }
}
function Set-ExecutionPolicyBypass {
    try {
        $currentPolicy = Get-ExecutionPolicy
        if ($currentPolicy -ne "Bypass") {
            Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
            Write-Log "Set execution policy to Bypass for current process" -Level Info
        }
    }
    catch {
        throw "Execution policy change failed: $_"
    }
}
function Test-AdminPrivileges {
    try {
        $identity = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        if (-not $identity.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw "Administrative privileges required"
        }
        Write-Log "Admin privileges verified" -Level Info
    }
    catch {
        throw "Admin check failed: $_"
    }
}
function Test-ArchitectureAndRelaunch {
    if ($Relaunched) {
        Write-Log "Running in 64 bit mode after relaunch" -Level Info
        return
    }

    if ($env:PROCESSOR_ARCHITEW6432 -eq "AMD64") {
        if (Test-Path "$env:WINDIR\SysNative\WindowsPowerShell\v1.0\powershell.exe") {
            Write-Log "Relaunching script in 64 bit PowerShell" -Level Info
            & "$env:WINDIR\SysNative\WindowsPowerShell\v1.0\powershell.exe" `
                -ExecutionPolicy Bypass `
                -NoProfile `
                -File $PSCommandPath `
                -Relaunched
            exit $LASTEXITCODE
        }
        else {
            Write-Log "SysNative PowerShell not found, continuing in current process" -Level Warning
        }
    }
}
function Get-ScriptDirectory {
    try {
        if ($PSCommandPath) {
            return (Split-Path -Parent $PSCommandPath)
        }
        else {
            return (Get-Location).Path
        }
    }
    catch {
        Write-Log "Failed to determine script directory: $($_.Exception.Message)" -Level Error
        [void]$script:failedOperations.Add("Determine script directory")
        throw
    }
}
function Test-AnyDeskPresence {
    [OutputType([bool])]
    param()

    [bool]$anyDeskDetected = $false

    try {
        # Check for running processes
        $anyDeskProcesses = Get-Process -Name $AnyDeskProcessNamePattern -ErrorAction SilentlyContinue
        if ($anyDeskProcesses) {
            foreach ($proc in $anyDeskProcesses) {
                Write-Log "Detected AnyDesk process '$($proc.ProcessName)' (Id=$($proc.Id))" -Level Info
            }
            $anyDeskDetected = $true
        }
        else {
            Write-Log "No running AnyDesk processes detected" -Level Info
        }

        # Check common install paths
        foreach ($path in $AnyDeskInstallPaths) {
            if ([string]::IsNullOrWhiteSpace($path)) { continue }
            try {
                if (Test-Path -Path $path) {
                    Write-Log "Detected AnyDesk binary at '$path'" -Level Info
                    $anyDeskDetected = $true
                }
            }
            catch {
                Write-Log "Error checking path '$path': $($_.Exception.Message)" -Level Warning
            }
        }

        # Check uninstall registry entries for AnyDesk
        foreach ($root in $AnyDeskUninstallRoots) {
            if (-not (Test-Path -Path $root)) { continue }

            try {
                Get-ChildItem -Path $root -ErrorAction SilentlyContinue | ForEach-Object {
                    try {
                        $props = Get-ItemProperty -Path $_.PsPath -ErrorAction SilentlyContinue
                        if ($props.DisplayName -like "*AnyDesk*") {
                            Write-Log "Detected AnyDesk uninstall entry '$($props.DisplayName)' under '$root'" -Level Info
                            $anyDeskDetected = $true
                        }
                    }
                    catch {
                        Write-Log "Error inspecting uninstall entry '$($_.Name)': $($_.Exception.Message)" -Level Warning
                    }
                }
            }
            catch {
                Write-Log "Error scanning uninstall root '$root': $($_.Exception.Message)" -Level Warning
            }
        }

        if ($anyDeskDetected) {
            Write-Log "AnyDesk presence detected on this device" -Level Info
        }
        else {
            Write-Log "No obvious AnyDesk traces detected, removal will still be attempted" -Level Info
        }
    }
    catch {
        Write-Log "Unexpected error during AnyDesk detection: $($_.Exception.Message)" -Level Error
        [void]$script:failedOperations.Add("AnyDesk detection")
    }

    return $anyDeskDetected
}
function Stop-AnyDeskProcesses {
    # Stop AnyDesk processes and services to avoid file locks
    try {
        # Stop service if present
        $serviceNames = @('AnyDesk')
        foreach ($svcName in $serviceNames) {
            try {
                $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
                if ($svc -and $svc.Status -ne 'Stopped') {
                    Stop-Service -Name $svcName -Force -ErrorAction Stop
                    Write-Log "Stopped AnyDesk service '$svcName'" -Level Info
                }
            }
            catch {
                Write-Log "Failed to stop AnyDesk service '$svcName': $($_.Exception.Message)" -Level Warning
                [void]$script:failedOperations.Add("Stop service $svcName")
            }
        }

        # Stop processes
        $anyDeskProcesses = Get-Process -Name $AnyDeskProcessNamePattern -ErrorAction SilentlyContinue
        if ($anyDeskProcesses) {
            foreach ($proc in $anyDeskProcesses) {
                try {
                    Stop-Process -Id $proc.Id -Force -ErrorAction Stop
                    Write-Log "Stopped AnyDesk process '$($proc.ProcessName)' (Id=$($proc.Id))" -Level Info
                }
                catch {
                    Write-Log "Failed to stop AnyDesk process '$($proc.ProcessName)' (Id=$($proc.Id)): $($_.Exception.Message)" -Level Error
                    [void]$script:failedOperations.Add("Stop process: $($proc.ProcessName) Id=$($proc.Id)")
                }
            }
        }
        else {
            Write-Log "No AnyDesk processes running, nothing to stop" -Level Info
        }
    }
    catch {
        Write-Log "Unexpected error in Stop-AnyDeskProcesses: $($_.Exception.Message)" -Level Error
        [void]$script:failedOperations.Add("Stop-AnyDeskProcesses general failure")
    }
}
function Add-AnyDeskFirewallBlocks {
    # Add firewall rules to block AnyDesk.exe inbound and outbound
    try {
        if (-not (Get-Command -Name New-NetFirewallRule -ErrorAction SilentlyContinue)) {
            Write-Log "New-NetFirewallRule cmdlet not available, skipping firewall configuration" -Level Warning
            [void]$script:failedOperations.Add("Firewall configuration (NetSecurity module unavailable)")
            return
        }

        Write-Log "Configuring firewall rules to block AnyDesk traffic" -Level Info

        $programPathsToBlock = @()

        # Known install paths
        foreach ($path in $AnyDeskInstallPaths) {
            if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path)) {
                $programPathsToBlock += $path
            }
        }

        # Service ImagePath if present
        try {
            $svcKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\AnyDesk'
            if (Test-Path -LiteralPath $svcKey) {
                $svcProps = Get-ItemProperty -Path $svcKey -ErrorAction SilentlyContinue
                if ($svcProps.ImagePath) {
                    $rawImagePath = $svcProps.ImagePath.Trim()
                    $serviceExe   = $null

                    if ($rawImagePath.StartsWith('"')) {
                        $serviceExe = ($rawImagePath -split '"')[1]
                    }
                    else {
                        $serviceExe = ($rawImagePath -split '\s+')[0]
                    }

                    if (-not [string]::IsNullOrWhiteSpace($serviceExe) -and (Test-Path -LiteralPath $serviceExe)) {
                        $programPathsToBlock += $serviceExe
                    }
                }
            }
        }
        catch {
            Write-Log "Failed to inspect AnyDesk service ImagePath for firewall rule: $($_.Exception.Message)" -Level Warning
        }

        # AnyDesk.exe in user Downloads folders
        try {
            Get-ChildItem $UserProfilesRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $downloadExe = Join-Path $_.FullName 'Downloads\AnyDesk.exe'
                if (Test-Path -LiteralPath $downloadExe) {
                    $programPathsToBlock += $downloadExe
                }
            }
        }
        catch {
            Write-Log "Error enumerating user Downloads for firewall rules: $($_.Exception.Message)" -Level Warning
        }

        $programPathsToBlock = $programPathsToBlock |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique

        if (-not $programPathsToBlock) {
            Write-Log "No AnyDesk executables found for firewall blocking" -Level Info
            return
        }

        $index = 0
        foreach ($programPath in $programPathsToBlock) {
            $index++
            $ruleNameIn  = "Block AnyDesk Inbound $index"
            $ruleNameOut = "Block AnyDesk Outbound $index"

            try {
                $existingIn  = Get-NetFirewallRule -DisplayName $ruleNameIn  -ErrorAction SilentlyContinue
                $existingOut = Get-NetFirewallRule -DisplayName $ruleNameOut -ErrorAction SilentlyContinue

                if (-not $existingIn) {
                    Write-Log "Creating inbound firewall rule '$ruleNameIn' for '$programPath'" -Level Info
                    New-NetFirewallRule `
                        -DisplayName $ruleNameIn `
                        -Direction Inbound `
                        -Action Block `
                        -Program $programPath `
                        -Profile Domain,Private,Public `
                        -Enabled True | Out-Null
                }
                else {
                    Write-Log "Inbound firewall rule '$ruleNameIn' already exists" -Level Info
                }

                if (-not $existingOut) {
                    Write-Log "Creating outbound firewall rule '$ruleNameOut' for '$programPath'" -Level Info
                    New-NetFirewallRule `
                        -DisplayName $ruleNameOut `
                        -Direction Outbound `
                        -Action Block `
                        -Program $programPath `
                        -Profile Domain,Private,Public `
                        -Enabled True | Out-Null
                }
                else {
                    Write-Log "Outbound firewall rule '$ruleNameOut' already exists" -Level Info
                }
            }
            catch {
                Write-Log "Failed to create firewall rules for '$programPath': $($_.Exception.Message)" -Level Warning
                [void]$script:failedOperations.Add("Firewall rule for $programPath")
            }
        }
    }
    catch {
        Write-Log "Unexpected error in Add-AnyDeskFirewallBlocks: $($_.Exception.Message)" -Level Error
        [void]$script:failedOperations.Add("Add-AnyDeskFirewallBlocks general failure")
    }
}
function Remove-AnyDeskDownloadBinaries {
    # Delete AnyDesk.exe from all user Downloads folders
    try {
        Write-Log "Removing AnyDesk.exe from user Downloads folders (if present)" -Level Info

        Get-ChildItem $UserProfilesRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $downloadExe = Join-Path $_.FullName 'Downloads\AnyDesk.exe'
            try {
                if (Test-Path -LiteralPath $downloadExe) {
                    Write-Log "Deleting '$downloadExe'" -Level Info
                    Remove-Item -LiteralPath $downloadExe -Force -ErrorAction Stop
                }
            }
            catch {
                Write-Log "Failed to delete '$downloadExe': $($_.Exception.Message)" -Level Warning
                [void]$script:failedOperations.Add("Remove download binary $downloadExe")
            }
        }
    }
    catch {
        Write-Log "Unexpected error in Remove-AnyDeskDownloadBinaries: $($_.Exception.Message)" -Level Error
        [void]$script:failedOperations.Add("Remove-AnyDeskDownloadBinaries general failure")
    }
}
function Start-AnyDeskRemoval {
    # Locate AnyDesk uninstall entries, execute them, and clean leftovers
    try {
        Write-Log "Starting AnyDesk uninstall phase" -Level Info

        $uninstallEntries = @()

        foreach ($root in $AnyDeskUninstallRoots) {
            if (-not (Test-Path -Path $root)) { continue }

            try {
                Get-ChildItem -Path $root -ErrorAction SilentlyContinue | ForEach-Object {
                    try {
                        $props = Get-ItemProperty -Path $_.PsPath -ErrorAction SilentlyContinue
                        if ($props.DisplayName -like "*AnyDesk*") {
                            $uninstallEntries += $props
                            Write-Log "Found AnyDesk uninstall entry '$($props.DisplayName)' in '$root'" -Level Info
                        }
                    }
                    catch {
                        Write-Log "Error inspecting uninstall entry '$($_.Name)': $($_.Exception.Message)" -Level Warning
                    }
                }
            }
            catch {
                Write-Log "Error scanning uninstall root '$root': $($_.Exception.Message)" -Level Warning
            }
        }

        if (-not $uninstallEntries) {
            Write-Log "No AnyDesk uninstall entries found in registry" -Level Warning
        }
        else {
            foreach ($entry in $uninstallEntries | Sort-Object DisplayName -Unique) {
                $uninstallString = $entry.UninstallString
                if ([string]::IsNullOrWhiteSpace($uninstallString)) {
                    Write-Log "Uninstall entry '$($entry.DisplayName)' does not expose an UninstallString" -Level Warning
                    [void]$script:failedOperations.Add("Missing UninstallString for $($entry.DisplayName)")
                    continue
                }

                try {
                    Write-Log "Invoking uninstall for '$($entry.DisplayName)' using UninstallString: $uninstallString" -Level Info

                    if ($uninstallString -match 'MsiExec\.exe') {
                        $parts = $uninstallString -split '\s+'
                        $exe = $parts[0]
                        $msiArguments = $parts[1..($parts.Length - 1)]

                        $msiArguments = $msiArguments | ForEach-Object {
                            if ($_ -match '^/I') { $_ -replace '/I', '/X' } else { $_ }
                        }

                        if ($msiArguments -notcontains '/qn' -and $msiArguments -notcontains '/quiet') {
                            $msiArguments += '/qn'
                        }

                        Start-Process -FilePath $exe -ArgumentList $msiArguments -Wait
                    }
                    else {
                        $cmd          = $uninstallString.Trim()
                        $exe          = $null
                        $exeArguments = ""

                        if ($cmd.StartsWith('"')) {
                            $exe = ($cmd -split '"')[1]
                            $exeArguments = $cmd.Substring($exe.Length + 2).Trim()
                        }
                        else {
                            $firstSpace = $cmd.IndexOf(' ')
                            if ($firstSpace -gt 0) {
                                $exe = $cmd.Substring(0, $firstSpace)
                                $exeArguments = $cmd.Substring($firstSpace + 1).Trim()
                            }
                            else {
                                $exe = $cmd
                            }
                        }

                        if (-not [string]::IsNullOrWhiteSpace($exeArguments)) {
                            if ($exeArguments -notmatch '/S' -and $exeArguments -notmatch '/silent' -and $exeArguments -notmatch '/quiet') {
                                $exeArguments = "$exeArguments /S"
                            }
                        }
                        else {
                            $exeArguments = "/S"
                        }

                        Write-Log "Starting process '$exe' with args '$exeArguments'" -Level Info
                        Start-Process -FilePath $exe -ArgumentList $exeArguments -Wait
                    }
                }
                catch {
                    Write-Log "Error invoking uninstall for '$($entry.DisplayName)': $($_.Exception.Message)" -Level Error
                    [void]$script:failedOperations.Add("Uninstall $($entry.DisplayName)")
                }
            }
        }

        Write-Log "Starting AnyDesk filesystem and registry cleanup" -Level Info

        # Filesystem cleanup
        $pathsToRemove = @(
            "$env:ProgramFiles\AnyDesk",
            "$env:ProgramFiles(x86)\AnyDesk",
            "$env:ProgramData\AnyDesk"
        )

        try {
            Get-ChildItem $UserProfilesRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $roamingPath = Join-Path $_.FullName 'AppData\Roaming\AnyDesk'
                $localPath   = Join-Path $_.FullName 'AppData\Local\AnyDesk'
                $pathsToRemove += $roamingPath
                $pathsToRemove += $localPath
            }
        }
        catch {
            Write-Log "Error enumerating user profiles for cleanup: $($_.Exception.Message)" -Level Warning
        }

        $pathsToRemove = $pathsToRemove |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique

        foreach ($path in $pathsToRemove) {
            try {
                if (Test-Path -LiteralPath $path) {
                    Write-Log "Removing path '$path'" -Level Info
                    Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
                }
            }
            catch {
                Write-Log "Failed to remove '$path': $($_.Exception.Message)" -Level Warning
                [void]$script:failedOperations.Add("Remove path $path")
            }
        }

        # Registry cleanup for service key
        $serviceKeyPaths = @(
            'HKLM:\SYSTEM\CurrentControlSet\Services\AnyDesk'
        )

        foreach ($svcKey in $serviceKeyPaths) {
            try {
                if (Test-Path -LiteralPath $svcKey) {
                    Write-Log "Removing service registry key '$svcKey'" -Level Info
                    Remove-Item -LiteralPath $svcKey -Recurse -Force -ErrorAction Stop
                }
            }
            catch {
                Write-Log "Failed to remove service key '$svcKey': $($_.Exception.Message)" -Level Warning
                [void]$script:failedOperations.Add("Remove service key $svcKey")
            }
        }

        # Startup Run entries
        $runKeys = @(
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
        )

        foreach ($rk in $runKeys) {
            try {
                if (Test-Path -Path $rk) {
                    Remove-ItemProperty -Path $rk -Name 'AnyDesk' -ErrorAction SilentlyContinue
                    Write-Log "Removed AnyDesk startup value from '$rk'" -Level Info
                }
            }
            catch {
                Write-Log "Error removing startup value from '$rk': $($_.Exception.Message)" -Level Warning
                [void]$script:failedOperations.Add("Remove startup entry in $rk")
            }
        }

        Write-Log "AnyDesk removal routine completed" -Level Info
    }
    catch {
        Write-Log "Unexpected error in Start-AnyDeskRemoval: $($_.Exception.Message)" -Level Error
        [void]$script:failedOperations.Add("Start-AnyDeskRemoval general failure")
    }
}

# ============================================================================================
# MAIN EXECUTION
# ============================================================================================
try {
    Write-Log "Starting AnyDesk cleanup script ($Version)" -Level Info
    Write-Log "Preparing environment for AnyDesk removal" -Level Info

    Initialize-LogDirectory
    Set-ExecutionPolicyBypass
    Test-AdminPrivileges
    Test-ArchitectureAndRelaunch

    $anyDeskDetectedBefore = Test-AnyDeskPresence

    if ($anyDeskDetectedBefore) {
        Stop-AnyDeskProcesses
    }

    # 1 - Block AnyDesk.exe via firewall (inbound and outbound)
    if (-not $SkipFirewall) {
        Add-AnyDeskFirewallBlocks
    }
    else {
        Write-Log "SkipFirewall constant is set, skipping firewall rule configuration" -Level Info
    }

    # 2 - Perform uninstall and filesystem/registry cleanup
    if (-not $SkipUninstall) {
        Start-AnyDeskRemoval
    }
    else {
        Write-Log "SkipUninstall constant is set, skipping uninstall and primary cleanup" -Level Info
    }

    # 3 - Delete AnyDesk.exe from user Downloads folders
    if (-not $SkipDownloadsCleanup) {
        Remove-AnyDeskDownloadBinaries
    }
    else {
        Write-Log "SkipDownloadsCleanup constant is set, skipping removal of Downloads AnyDesk.exe" -Level Info
    }

    $anyDeskDetectedAfter = Test-AnyDeskPresence
    if ($anyDeskDetectedAfter) {
        Write-Log "AnyDesk traces still detected after removal routine" -Level Warning
        [void]$script:failedOperations.Add("AnyDesk still detected after cleanup")
    }
    else {
        Write-Log "No AnyDesk traces detected after removal routine" -Level Info
    }

    if ($script:failedOperations.Count -gt 0) {
        Write-Log "Completed with $($script:failedOperations.Count) operation failures: $($script:failedOperations -join ', ')" -Level Warning
    }
    else {
        Write-Log "AnyDesk cleanup completed successfully" -Level Info
    }

    Write-Log "Ending AnyDesk cleanup script" -Level Info
}
catch {
    $errorMsg = "SCRIPT FAILURE: $($_.Exception.Message)"
    Write-Log $errorMsg -Level Error
    Write-Log "Stack trace:`n$($_.ScriptStackTrace)" -Level Error
}
finally {
    Write-Log "Script execution completed" -Level Info
    Add-Content -Path $LogPath -Value (" ")
    exit 0
}
