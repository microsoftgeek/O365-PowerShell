Write-Output "$HR CDI Remove O365 Licenses

##########################################################################################
#
#                  *CDI Remove O365 Licenses* 
#                                                                                
# Created by Cesar Duran (Jedi Master)                                                                                        
# Version:1.0                                                                                                                                       
#                                                                                                                                                                                                                                                              
# CDI Script Tasks:
# 1) Get AD users
# 2) Remove O365 Licenses
#                                                                                                                                                                                                                                                                                                                                                                                                                                 
#                                                                                                                                                                                                          
###########################################################################################

$HR"


# Line delimiter
$HR = "`n{0}`n" -f ('='*20)


########################################
Write-Output "$HR CONNECT O365 LICENSE $HR"

#Get credentails and connect
$Creds = Get-Credential
Connect-MsolService -Credential $Creds
Connect-AzureAD -Credential $Creds



########################################
Write-Output "$HR REMOVE O365 LICENSE $HR"

$users = Import-Csv .\Users-to-disable.csv
 
foreach ($user in $users) {
Write-Verbose "Processing licenses for user $($user.UserPrincipalName)"
try { $user = Get-MsolUser -UserPrincipalName $user.UserPrincipalName -ErrorAction Stop }
catch { continue }
 
$SKUs = @($user.Licenses)
if (!$SKUs) { Write-Verbose "No Licenses found for user $($user.UserPrincipalName), skipping..." ; continue }
 
foreach ($SKU in $SKUs) {
if (($SKU.GroupsAssigningLicense.Guid -ieq $user.ObjectId.Guid) -or (!$SKU.GroupsAssigningLicense.Guid)) {
Write-Verbose "Removing license $($Sku.AccountSkuId) from user $($user.UserPrincipalName)"
Set-MsolUserLicense -UserPrincipalName $user.UserPrincipalName -RemoveLicenses $SKU.AccountSkuId
}
else {
Write-Verbose "License $($Sku.AccountSkuId) is assigned via Group, use the Azure AD blade to remove it!"
continue
}
}
}
# end of remove license


###################################################
Write-Output "$HR THE END, HAVE A NICE DAY!!!

##########################################################################################
#
#              *POWERFUL YOU HAVE BECOME, THE DARK SIDE I SENSE IN YOU - YODA*
#
#                                                                                                                                                                                                                                                                                                                                                                                                                              
#                                                                                                                                                                                                          
###########################################################################################

$HR"