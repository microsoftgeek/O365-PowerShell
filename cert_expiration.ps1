Import-Module AzureAD

Connect-AzureAD

#Change this to the number of days out you want to look
$daysOut = 30


#Main Script#
$doneID = ""
$countExpiring = 0

$allSAMLApps = Get-AzureADServicePrincipal -All $true | Where-Object {($_.Tags -contains "WindowsAzureActiveDirectoryGalleryApplicationNonPrimaryV1") -or ($_.Tags -contains "WindowsAzureActiveDirectoryCustomSingleSignOnApplication")}

Write-Host "Looking for certs that expire by ((Get-Date).AddDays($daysOut))" -ForegroundColor Green
foreach ($singleApp in $allSAMLApps) {
    
    foreach ($KeyCredential in $singleApp.KeyCredentials) {
        
        if ( $KeyCredential.EndDate -lt (Get-Date).AddDays($daysOut) ) {
            if (($singleApp.ObjectId) -ne $doneID) {
                Write-Host " Name: " ($singleApp.DisplayName) " - Experation: " $KeyCredential.EndDate
                $doneID = ($singleApp.ObjectId)
                $countExpiring = $countExpiring + 1
            }
        }

    }

}

Write-Host "There are $countExpiring certs." -ForegroundColor Green 