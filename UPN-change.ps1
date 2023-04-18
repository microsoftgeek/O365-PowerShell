# Make sure dependencies are installed
#Install-Module AzureAD
Import-Module AzureAD

# Read in old and new username
$Existing = Read-Host -Prompt "What is the old username?"
$Change = Read-Host -Prompt "What is the new username?"

# Change username to UPN if needed
if ($Existing -notlike "*@*"){
    $Existing = $Existing + "@" + $env:USERDNSDOMAIN.ToLower()
}
if ($Change -notlike "*@*"){
    $Change = $Change + "@" + $env:USERDNSDOMAIN.ToLower()
}
Clear-Host
# Get-Credentials
Connect-AzureAD
# Check for existing object in AzureAD
$AAD_User = Get-AzureADUser -ObjectId $Existing
# Change Object only if exists
if ($AAD_User.Count -eq 1){
    Set-AzureADUser -ObjectId $Existing -UserPrincipalName $Change
}