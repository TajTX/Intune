# Script Purpose:
# Connects to Microsoft Graph via PowerShell SDK, retrieves members of Entra ID groups
# whose names start with a given prefix, and exports results to a CSV file in horizontal format.
# Requirements:
# - Install Microsoft.Graph PowerShell module: Install-Module Microsoft.Graph -Scope CurrentUser
# - Sign in with scopes: Group.Read.All, User.Read.All, Device.Read.All
# Usage:
# 1. Run script, enter prefix for group names when prompted.
# 2. Output file: GroupMembers.csv
Connect-MgGraph -Scopes "Group.Read.All","User.Read.All","Device.Read.All"

$groupPrefix = Read-Host "Enter starting text for group names"

$groups = Get-MgGroup -Filter "startswith(displayName,'$groupPrefix')" -All

if (-not $groups) {
    Write-Host "No groups found starting with '$groupPrefix'"
    exit
}

$output = @()

foreach ($group in $groups) {
    Write-Host "Processing group: $($group.DisplayName)"

    $members = Get-MgGroupMember -GroupId $group.Id -All

    $row = @{ GroupName = $group.DisplayName }
    $i = 1

    foreach ($member in $members) {
        switch ($member.AdditionalProperties.'@odata.type') {
            "#microsoft.graph.user" {
                $user = Get-MgUser -UserId $member.Id
                $row["Member$i"] = $user.DisplayName
            }
            "#microsoft.graph.device" {
                $device = Get-MgDevice -DeviceId $member.Id
                $row["Member$i"] = $device.DisplayName
            }
            default {
                $row["Member$i"] = "UnknownType"
            }
        }
        $i++
    }

    $output += New-Object PSObject -Property $row
}

$csvPath = "GroupMembers.csv"
$output | Export-Csv -Path $csvPath -NoTypeInformation
Write-Host "Export complete! File saved to $csvPath"
