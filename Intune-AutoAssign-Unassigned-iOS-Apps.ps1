<#
DISCLAIMER:
This script is provided "as is" without warranty of any kind, express or implied. Use this script at your own risk.
The author and contributors are not responsible for any damage or issues potentially caused by the use of this script.
Always test scripts in a non-production environment before deploying them into a production setting.
#>
<#
This script connects to Microsoft Graph and retrieves all iOS/iPadOS apps from Intune. It exports the app list to a CSV file and identifies apps that are not currently assigned. 
For each unassigned app, it creates two security groups in Entra ID—one user group and one device group based on the app name. 
It then assigns the app to the user group as “Available” and to the device group as “Required,” applying appropriate Intune iOS assignment settings for each app type. 
The script also handles different iOS app types and ensures only valid Graph-supported properties are used during assignment.
#>
############################################################
# CONNECT TO GRAPH
############################################################

Connect-MgGraph -Scopes `
"DeviceManagementApps.ReadWrite.All",
"Group.ReadWrite.All"

Select-MgProfile beta

############################################################
# OUTPUT PATH
############################################################

$ExportPath = "C:\Temp\IntuneiOSApps.csv"

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

Write-Host "iOS apps found: $($iOSApps.Count)" -ForegroundColor Green

############################################################
# EXPORT CSV (FIXED)
############################################################

$iOSApps | ForEach-Object {
    [PSCustomObject]@{
        DisplayName = $_.displayName
        Id          = $_.id
        AppType     = $_.'@odata.type'
        IsAssigned  = $_.isAssigned
    }
} | Export-Csv $ExportPath -NoTypeInformation

Write-Host "CSV exported to $ExportPath" -ForegroundColor Green

############################################################
# FILTER UNASSIGNED APPS
############################################################

$UnassignedApps = $iOSApps | Where-Object { $_.isAssigned -eq $false }

Write-Host "Unassigned apps: $($UnassignedApps.Count)" -ForegroundColor Yellow

############################################################
# PROCESS EACH APP
############################################################

foreach ($App in $UnassignedApps) {

    Write-Host "`nProcessing: $($App.displayName)" -ForegroundColor Cyan

    try {
        ########################################################
        # CREATE GROUP NAMES
        ########################################################

        $SafeName = $App.displayName -replace '[\\\/\:\*\?\"\<\>\|]', '' -replace '\s+', ' '

        $UserGroupName   = "Intune App $SafeName User"
        $DeviceGroupName = "Intune App $SafeName Device"

        ########################################################
        # CREATE GROUPS
        ########################################################

        $UserGroup = New-MgGroup -DisplayName $UserGroupName `
            -MailEnabled:$false `
            -MailNickname ($UserGroupName -replace ' ','') `
            -SecurityEnabled:$true

        $DeviceGroup = New-MgGroup -DisplayName $DeviceGroupName `
            -MailEnabled:$false `
            -MailNickname ($DeviceGroupName -replace ' ','') `
            -SecurityEnabled:$true

        ########################################################
        # DETERMINE SETTINGS TYPE (IMPORTANT FIX)
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
        # BUILD ASSIGNMENTS (CLEAN + VALID)
        ########################################################

        $Body = @{
            mobileAppAssignments = @(
                
                # USER - Available
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

                # DEVICE - Required
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

        Invoke-MgGraphRequest -Method POST `
            -Uri $Uri `
            -Body ($Body | ConvertTo-Json -Depth 20) `
            -ContentType "application/json"

        Write-Host "Success: $($App.displayName)" -ForegroundColor Green
    }
    catch {
        Write-Host "FAILED: $($App.displayName)" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Yellow
    }
}

Write-Host "`nCompleted processing all apps." -ForegroundColor Green
