#To get a list of assigned iOS Store and VPP Apps and their categories

# Import the MSAL.PS module
Import-Module MSAL.PS

# Define the required variables
$TenantId = "<Your-Tenant-ID>"
$ClientId = "<Your-App-Client-ID>"
$ClientSecret = "<Your-App-Client-Secret>"
$Scope = "https://graph.microsoft.com/.default"

# Convert the ClientSecret to a SecureString
$SecureClientSecret = ConvertTo-SecureString $ClientSecret -AsPlainText -Force

# Get the authentication token
$AuthResponse = Get-MsalToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $SecureClientSecret -Scopes $Scope
$AccessToken = $AuthResponse.AccessToken

# Define the Graph API URLs
$BaseUrl = "https://graph.microsoft.com/v1.0/deviceAppManagement"
$CategoriesUrl = "$BaseUrl/mobileAppCategories"
$AppsUrl = "$BaseUrl/mobileApps"

# Function to make API calls
function Invoke-GraphApi {
    param (
        [string]$Url
    )
    $Headers = @{
        Authorization = "Bearer $AccessToken"
    }
    $Response = Invoke-RestMethod -Uri $Url -Headers $Headers -Method GET
    return $Response
}

# Get the app categories
$Categories = Invoke-GraphApi -Url $CategoriesUrl
$CategoryMapping = @{}
foreach ($Category in $Categories.value) {
    $CategoryMapping[$Category.id] = $Category.displayName
}

# Get all apps
$Apps = Invoke-GraphApi -Url $AppsUrl
$AppDetails = @()

# Define iOS-specific app types (adjust based on findings)
$iOSAppTypes = @(
    "#microsoft.graph.managedIOSStoreApp",
    "#microsoft.graph.iosVppApp"
)

foreach ($App in $Apps.value) {
    # Filter for iOS apps
    if ($App.'@odata.type' -notin $iOSAppTypes) {
        continue
    }

    $AppId = $App.id

    # Check if the app has assignments
    $AssignmentsUrl = "$AppsUrl/$AppId/assignments"
    $Assignments = Invoke-GraphApi -Url $AssignmentsUrl

    # Skip apps with no assignments
    if (-not $Assignments.value) {
        continue
    }

    # Get app categories
    $AppCategoriesUrl = "$AppsUrl/$AppId/categories"
    $AppCategoriesResponse = Invoke-GraphApi -Url $AppCategoriesUrl

    $CategoryNames = if ($AppCategoriesResponse.value) {
        $AppCategoriesResponse.value | ForEach-Object { $_.displayName }
    } else {
        @("No Categories Assigned")
    }

    # Add app details to the output array
    $AppDetails += [PSCustomObject]@{
        AppName       = $App.displayName
        AppId         = $AppId
        Categories    = ($CategoryNames -join ", ")
    }
}

# Output the app details
$AppDetails | Format-Table -AutoSize

# Optionally, export to CSV
$AppDetails | Export-Csv -Path "AssignedIntuneiOSAppsAndCategories.csv" -NoTypeInformation
