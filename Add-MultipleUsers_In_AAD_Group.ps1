<#

Description - script to add multiple user emails in any Static AAD group

.Example
.\Add-MultipleUsers_In_AAD_Group.ps1 -path "C:\Temp\AADGroup-AddDevice\USERS.txt" -AADGroupId "622b1654-c13a-4f6f-8423-578fd0eeda88"

Run below commands to install graph modules -
Install-Module -Name "Microsoft.Graph.Authentication" -Scope AllUsers -Force
Install-Module -Name "Microsoft.Graph.Groups" -Scope AllUsers -Force
Install-Module -Name "Microsoft.Graph.Users" -Scope AllUsers -Force

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

$reportfile="$env:systemdrive\Temp\Bulk_Add_AAD-Users.csv"

$users=gc $path | where{$_ -ne ''}
Write-Output "Found total users - $(($users | measure).count)"

$grpid=$AADGroupId

$result=@()
foreach($user in $users){

$user_obj=$null
$user_obj=Get-MgUser -filter "userprincipalname eq '$user'" | select -ExpandProperty Id

if($user_obj){
try{
New-MgGroupMember  -GroupId $grpid -DirectoryObjectId $user_obj -ErrorAction Stop

$result+=[pscustomobject]@{
DeviceName=$user
ObjectID=$user_obj
Status='Added'
}

Write-Output "Added user - $user"

}
catch
{
$err=$_.exception.message
Write-Output "failed to add user - $user"
$failed_device_name+=$user

$result+=[pscustomobject]@{
DeviceName=$user
ObjectID=$user_obj
Status=$err
}
}
}
else
{
$result+=[pscustomobject]@{
DeviceName=$user
ObjectID=$null
Status='User not Found in AAD'
}

Write-Output "$user is Not Found in AAD"

}

}

Write-Output "Below is the status of script:-"
$result

if($result){
$result | Export-Csv -Path $reportfile -Force -NoTypeInformation
Write-Output "Status Report is created in loc - '$reportfile'"
}

}
else
{
Write-Output "Please specify txt file path and retry again."
}

