<#
DISCLAIMER:
This script is provided "as is" without warranty of any kind, express or implied. Use this script at your own risk.
The author and contributors are not responsible for any damage or issues potentially caused by the use of this script.
Always test scripts in a non-production environment before deploying them into a production setting.
#>
<#
.SYNOPSIS
    This PowerShell script retrieves Windows Intune devices for a list of specified users
    and adds those devices to a newly created Azure AD security group.

.DESCRIPTION
    The script performs the following actions:

    1. Prompts the administrator for a name for the new device group.
    2. Reads a list of user principal names (UPNs) from a text file.
    3. Connects to Microsoft Graph using the Microsoft Graph PowerShell SDK.
    4. Resolves each UPN to its corresponding Azure AD user object.
    5. Queries Intune to retrieve all managed devices.
    6. Filters devices to include only Windows devices.
    7. Identifies devices where the user is set as the Primary User.
    8. Exports the list of matched devices to a CSV file for auditing and reference.
    9. Creates a new Azure AD security group with the specified name.
    10. Maps the Intune devices to Azure AD device objects using AzureADDeviceId.
    11. Adds the mapped devices as members of the new security group.
    12. Provides a summary of actions, including the number of devices found, added, or skipped.

.NOTES
    - Requires Microsoft.Graph PowerShell SDK installed.
    - Requires permissions: Device.Read.All, User.Read.All, Group.ReadWrite.All
    - Only supports Windows devices.
    - Ensures that devices are properly mapped to their Azure AD directory object IDs before adding to the group.
    - Skips devices that are not Azure AD joined or already members of the group.

.EXAMPLE
    Run the script and provide the text file path and new group name when prompted.
    The script will create a new device group containing all Windows devices where the listed users are primary users.

#>

# ===============================
# Prompt for Group Name
# ===============================
$GroupName = Read-Host "Enter the name for the new device group"
$GroupDesc = "Devices where specified users are primary users (Windows only)"

# ===============================
# Configuration
# ===============================
$UserListPath = "C:\PowerShell\users.txt"
$OutputCsv    = "C:\PowerShell\PrimaryUsers1.csv"

# ===============================
# Connect to Graph
# ===============================
Write-Host "Connecting to Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes "Group.ReadWrite.All","Directory.Read.All","Device.Read.All","User.Read.All"

# ===============================
# Read input users
# ===============================
$UserEntries = Get-Content $UserListPath | Where-Object { $_.Trim() -ne "" }

# ===============================
# Resolve users
# ===============================
Write-Host "Resolving users..." -ForegroundColor Cyan
$UserObjects = foreach ($entry in $UserEntries) {
    $u = Get-MgUser -Filter "userPrincipalName eq '$entry'" -ConsistencyLevel eventual
    if ($u) { $u } else { Write-Warning "User not found: $entry" }
}

# ===============================
# Get ALL Intune devices (Windows only)
# ===============================
Write-Host "Retrieving all managed Windows devices..." -ForegroundColor Cyan
$AllDevicesRaw = Get-MgDeviceManagementManagedDevice -All
$AllDevices = $AllDevicesRaw | Where-Object { $_.OperatingSystem -eq "Windows" }

Write-Host "Total Windows devices retrieved: $($AllDevices.Count)" -ForegroundColor Green

# ===============================
# Match devices by user ID
# ===============================
$MatchedDevices = foreach ($user in $UserObjects) {
    $AllDevices | Where-Object { $_.UserId -eq $user.Id }
}

# Export CSV for convenience
$MatchedDevices | Select-Object `
    DeviceName, UserId, OperatingSystem, Model, ComplianceState, LastSyncDateTime, AzureADDeviceId |
    Export-Csv -Path $OutputCsv -NoTypeInformation
Write-Host "Results exported to $OutputCsv" -ForegroundColor Green

# ===============================
# Create new Entra Security Group
# ===============================
Write-Host "Creating new device security group: $GroupName" -ForegroundColor Cyan

$NewGroup = New-MgGroup -DisplayName $GroupName `
    -Description $GroupDesc `
    -MailEnabled:$false `
    -SecurityEnabled:$true `
    -MailNickname ("grp" + (Get-Random))

Write-Host "Created Group ID: $($NewGroup.Id)" -ForegroundColor Green

# ===============================
# Add devices to the group (correct method)
# ===============================
Write-Host "Mapping Intune devices to Entra devices..." -ForegroundColor Cyan

# Get all AAD devices one time
$AllAADDevices = Get-MgDevice -All

$Added = 0
$Skipped = 0

foreach ($dev in $MatchedDevices) {

    if (-not $dev.AzureADDeviceId) {
        Write-Warning "Device $($dev.DeviceName) is NOT Azure AD joined (no AzureADDeviceId). Skipping."
        $Skipped++
        continue
    }

    # Match Intune device to Entra device object
    $aad = $AllAADDevices | Where-Object { $_.DeviceId -eq $dev.AzureADDeviceId }

    if (-not $aad) {
        Write-Warning "Cannot find Entra object for: $($dev.DeviceName). Skipping."
        $Skipped++
        continue
    }

    try {
        New-MgGroupMember -GroupId $NewGroup.Id -DirectoryObjectId $aad.Id -ErrorAction Stop
        Write-Host "Added: $($dev.DeviceName)" -ForegroundColor Green
        $Added++
    }
    catch {
        Write-Warning "Skipped (already member or error): $($dev.DeviceName)"
        $Skipped++
    }
}

# ===============================
# Summary
# ===============================
Write-Host "`n========== SUMMARY ==========" -ForegroundColor Cyan
Write-Host "Group Name:  $($NewGroup.DisplayName)"
Write-Host "Group ID:    $($NewGroup.Id)"
Write-Host "Windows Devices Found:   $($MatchedDevices.Count)"
Write-Host "Devices Added:           $Added"
Write-Host "Devices Skipped:         $Skipped"
Write-Host "================================`n" -ForegroundColor Cyan
