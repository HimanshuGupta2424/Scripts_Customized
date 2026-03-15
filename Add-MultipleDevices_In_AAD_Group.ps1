<#

Description - script to add multiple devices in any Static AAD group

.Example
.\Add-MultipleDevices_In_AAD_Group.ps1 -path "MachineList.txt" -AADGroupId "3dc7865e-ef8d-487b-9948-20ee5072cf3b"


Run below commands to install graph modules -
Install-Module -Name "Microsoft.Graph.Authentication" -Scope AllUsers -Force
Install-Module -Name "Microsoft.Graph.Groups" -Scope AllUsers -Force
Install-Module -Name "Microsoft.Graph.Identity.DirectoryManagement" -Scope AllUsers -Force

#>

[CmdletBinding()]
param
(
    [Parameter(Mandatory = $true)]
    [String]$path,
    [Parameter(Mandatory = $true)]
    [String]$AADGroupId
)

try{
Connect-MgGraph -ErrorAction Stop
}
catch
{
Write-Error "Failed to authenticate Mg Graph - $($_.exception.Message)"
return
}

$path=$path -replace "`"",""

if((Test-Path -Path "$env:systemdrive\Temp") -eq $false)
{
New-Item -Path "$env:systemdrive\Temp" -ItemType Directory -Force
}

if($path -like "*.txt"){
$reportfile="C:\Temp\AADGroup-AddDevice\Bulk_Add_AAD-Devices.csv"


$devices=gc $path | where{$_ -ne ''}

Write-Output "Found total devices - $(($devices | measure).count)"

if($devices)
{
$grpid=$AADGroupId


$result=@()
foreach($device in $devices){


$device_obj=$null

$device_obj=Get-MgDevice -filter "displayname eq '$device'" | select -ExpandProperty Id

if($device_obj){
try{
New-MgGroupMember -GroupId $grpid -DirectoryObjectId $device_obj -ErrorAction Stop

$result+=[pscustomobject]@{
DeviceName=$device
ObjectID=$device_obj
Status='Added'
}

Write-Output "Added device - $device"

}
catch
{
$err=$_.exception.message
Write-Output "failed to add device - $device"
$failed_device_name+=$device

$result+=[pscustomobject]@{
DeviceName=$device
ObjectID=$device_obj
Status=$err
}

}
}else
{
$result+=[pscustomobject]@{
DeviceName=$device
ObjectID=$null
Status='Device not Found in AAD'
}
Write-Output "$device is Not Found in AAD"
}
}

""
Write-Output "Below is the status of script:-"
$result

if($result){
$result | Export-Csv -Path $reportfile -Force -NoTypeInformation
Write-Output "Status Report is created in loc - '$reportfile'"
}

}
else
{
Write-Output "No devices found in txt file."
}
}
else
{
Write-Output "Please specify txt file path and retry again."
}