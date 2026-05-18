<#
DISCLAIMER:
This script is provided "as is" without warranty of any kind, express or implied. Use this script at your own risk.
The author and contributors are not responsible for any damage or issues potentially caused by the use of this script.
Always test scripts in a non-production environment before deploying them into a production setting.
#>
<#
This script connects to Microsoft Graph and retrieves all iOS/iPadOS apps from Intune. 
It identifies apps without assignments by validating each app’s assignment status, exports the unassigned apps to a CSV file for review, and prompts the administrator for confirmation before proceeding. 
Once approved, the script creates user and device Entra ID security groups for each unassigned app and assigns the apps in Intune using the appropriate iOS assignment settings based on the app type.
#>
############################################################
# CONNECT TO GRAPH
############################################################

Connect-MgGraph -Scopes `
"DeviceManagementApps.ReadWrite.All",
"Group.ReadWrite.All"

############################################################
# OUTPUT PATH
############################################################

$ExportPath = "C:\Temp\Unassigned-iOSApps.csv"

############################################################
# GET ALL MOBILE APPS
############################################################

Write-Host "Fetching Intune mobile apps..." -ForegroundColor Cyan

$Apps = (Invoke-MgGraphRequest -Method GET `
    -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps").value

############################################################
# FILTER IOS APPS
############################################################

$iOSApps = $Apps | Where-Object {
    $_.'@odata.type' -match "ios"
}

Write-Host "Total iOS apps found: $($iOSApps.Count)" -ForegroundColor Green

############################################################
# DETERMINE TRUE UNASSIGNED APPS
############################################################

$UnassignedApps = @()

foreach ($App in $iOSApps) {

    try {

        $Assignments = (Invoke-MgGraphRequest -Method GET `
            -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($App.id)/assignments").value

        if (-not $Assignments -or $Assignments.Count -eq 0) {

            $UnassignedApps += $App
        }
    }
    catch {

        Write-Host "Failed assignment lookup: $($App.displayName)" -ForegroundColor Red
    }
}

Write-Host "Unassigned apps found: $($UnassignedApps.Count)" -ForegroundColor Yellow

############################################################
# EXPORT CSV
############################################################

$UnassignedApps | ForEach-Object {

    [PSCustomObject]@{
        DisplayName = $_.displayName
        Id          = $_.id
        AppType     = $_.'@odata.type'
    }

} | Export-Csv $ExportPath -NoTypeInformation

Write-Host "CSV exported to: $ExportPath" -ForegroundColor Green

############################################################
# USER CONFIRMATION
############################################################

Write-Host ""
Write-Host "Review the CSV before continuing." -ForegroundColor Cyan

$Proceed = Read-Host "Do you want to continue with group creation and app assignments? (Y/N)"

if ($Proceed -ne "Y" -and $Proceed -ne "y") {

    Write-Host "Operation cancelled by user." -ForegroundColor Yellow
    return
}

############################################################
# PROCESS EACH APP
############################################################

foreach ($App in $UnassignedApps) {

    Write-Host "`nProcessing: $($App.displayName)" -ForegroundColor Cyan

    try {

        ########################################################
        # SAFE GROUP NAME
        ########################################################

        $SafeName = $App.displayName `
            -replace '[\\\/\:\*\?\"\<\>\|]', '' `
            -replace '\s+', ' '

        $UserGroupName   = "Intune App $SafeName User"
        $DeviceGroupName = "Intune App $SafeName Device"

        ########################################################
        # CHECK IF GROUPS EXIST
        ########################################################

        $ExistingUserGroup = Get-MgGroup `
            -Filter "displayName eq '$UserGroupName'"

        if (-not $ExistingUserGroup) {

            Write-Host "Creating User Group..." -ForegroundColor Gray

            $UserGroup = New-MgGroup `
                -DisplayName $UserGroupName `
                -MailEnabled:$false `
                -MailNickname ($UserGroupName -replace ' ','') `
                -SecurityEnabled:$true
        }
        else {

            Write-Host "User Group already exists." -ForegroundColor Yellow
            $UserGroup = $ExistingUserGroup
        }

        $ExistingDeviceGroup = Get-MgGroup `
            -Filter "displayName eq '$DeviceGroupName'"

        if (-not $ExistingDeviceGroup) {

            Write-Host "Creating Device Group..." -ForegroundColor Gray

            $DeviceGroup = New-MgGroup `
                -DisplayName $DeviceGroupName `
                -MailEnabled:$false `
                -MailNickname ($DeviceGroupName -replace ' ','') `
                -SecurityEnabled:$true
        }
        else {

            Write-Host "Device Group already exists." -ForegroundColor Yellow
            $DeviceGroup = $ExistingDeviceGroup
        }

        ########################################################
        # DETERMINE SETTINGS TYPE
        ########################################################

        switch ($App.'@odata.type') {

            "#microsoft.graph.iosVppApp" {
                $SettingsType = "#microsoft.graph.iosVppAppAssignmentSettings"
            }

            default {
                $SettingsType = "#microsoft.graph.iosStoreAppAssignmentSettings"
            }
        }

        ########################################################
        # BUILD ASSIGNMENT BODY
        ########################################################

        $Body = @{
            mobileAppAssignments = @(

                # USER ASSIGNMENT
                @{
                    "@odata.type" = "#microsoft.graph.mobileAppAssignment"
                    intent = "available"

                    target = @{
                        "@odata.type" = "#microsoft.graph.groupAssignmentTarget"
                        groupId = $UserGroup.Id
                    }

                    settings = @{
                        "@odata.type" = $SettingsType
                        preventManagedAppBackup = $true
                    }
                },

                # DEVICE ASSIGNMENT
                @{
                    "@odata.type" = "#microsoft.graph.mobileAppAssignment"
                    intent = "required"

                    target = @{
                        "@odata.type" = "#microsoft.graph.groupAssignmentTarget"
                        groupId = $DeviceGroup.Id
                    }

                    settings = @{
                        "@odata.type" = $SettingsType
                        uninstallOnDeviceRemoval = $true
                        preventManagedAppBackup = $true
                    }
                }
            )
        }

        ########################################################
        # ASSIGN APP
        ########################################################

        $Uri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($App.id)/assign"

        Invoke-MgGraphRequest `
            -Method POST `
            -Uri $Uri `
            -Body ($Body | ConvertTo-Json -Depth 20) `
            -ContentType "application/json"

        Write-Host "Assignment successful: $($App.displayName)" -ForegroundColor Green
    }
    catch {

        Write-Host "FAILED: $($App.displayName)" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Completed processing all apps." -ForegroundColor Green
