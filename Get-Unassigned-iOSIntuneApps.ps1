<#
DISCLAIMER:
This script is provided "as is" without warranty of any kind, express or implied. Use this script at your own risk.
The author and contributors are not responsible for any damage or issues potentially caused by the use of this script.
Always test scripts in a non-production environment before deploying them into a production setting.
#>
<#
This script retrieves all iOS/iPadOS apps from Microsoft Intune using Microsoft Graph and accurately identifies apps that do not have any assignments. 
It validates assignment status by checking each app’s assignment endpoint rather than relying on cached properties. 
The script then exports a clean report of unassigned apps, including app name, ID, and app type, for review or use in downstream automation processes.
#>
Connect-MgGraph -Scopes "DeviceManagementApps.Read.All"

$ExportPath = "C:\Temp\Unassigned-iOSApps.csv"

Write-Host "Getting Intune apps..." -ForegroundColor Cyan

$Apps = (Invoke-MgGraphRequest -Method GET `
    -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps").value

$iOSApps = $Apps | Where-Object { $_.'@odata.type' -match "ios" }

Write-Host "Total iOS apps: $($iOSApps.Count)" -ForegroundColor Green

$Unassigned = @()

foreach ($App in $iOSApps) {

    try {
        $Assignments = (Invoke-MgGraphRequest -Method GET `
            -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($App.id)/assignments").value
    }
    catch {
        Write-Host "Failed: $($App.displayName)" -ForegroundColor Red
        continue
    }

    if (-not $Assignments -or $Assignments.Count -eq 0) {

        $Unassigned += [PSCustomObject]@{
            DisplayName = $App.displayName
            Id          = $App.id
            AppType     = $App.'@odata.type'
        }
    }
}

Write-Host "Correct Unassigned Count: $($Unassigned.Count)" -ForegroundColor Yellow

$Unassigned | Export-Csv $ExportPath -NoTypeInformation

Write-Host "Exported to $ExportPath" -ForegroundColor Green
