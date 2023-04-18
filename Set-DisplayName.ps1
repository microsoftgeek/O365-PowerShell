# Make sure dependencies are installed
Install-Module AzureAD -Force -Verbose
Import-Module AzureAD -Force -Verbose
Connect-AzureAD

#MSONLINE
#Install-Module MsolService -Force -Verbose
#Import-Module MsolService -Force -Verbose
#Connect-MsolService

#script
$user = Get-AzureADUser -ObjectId Erik.Skomsoyvog@cabinetworksgroup.com 
$user.DisplayName = 'Erik Skomsoyvog'
Set-AzureADUser -ObjectId Erik.Skomsoyvog@cabinetworksgroup.com -Displayname $user.Displayname