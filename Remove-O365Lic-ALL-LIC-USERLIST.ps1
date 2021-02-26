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
Write-Output "$HR REMOVE O365 LICENSE $HR"


$Creds = Get-Credential
Connect-MsolService -Credential $Creds

$x = Get-Content "C:\temp\remove2.txt"
$userArray = Get-MsolUser -All $x | where {$_.isLicensed -eq $true}

for ($i=0; $i -lt $userArray.Count; $i++)
{
Set-MsolUserLicense -UserPrincipalName $userArray[$i].UserPrincipalName -RemoveLicenses $userArray[$i].licenses.accountskuid
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