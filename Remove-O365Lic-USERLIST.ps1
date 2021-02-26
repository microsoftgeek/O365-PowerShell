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

#Get credentails and connect
$Creds = Get-Credential
Connect-MsolService -Credential $Creds


$x = Get-Content "C:\temp\remove2.txt"
for ($i=0; $i -lt $x.Count; $i++)

{
Set-MsolUserLicense -UserPrincipalName $x[$i] -RemoveLicenses "cdirad:ENTERPRISEPACKWITHOUTPROPLUS"

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