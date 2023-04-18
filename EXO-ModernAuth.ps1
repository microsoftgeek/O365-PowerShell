########################################
Write-Output "$HR CONNECT TO EXO $HR"
########################################

#Connect to Exchange Online PowerShell with existing service principal and client-secret

#Step1: Get an OAuth access token using Active Directory Authentication Library (ADAL) PowerShell
Get-ADALAccessToken -AuthorityName contoso.onmicrosoft.com -ClientId 8f710b23-d3ea-4dd3-8a0e-c5958a6bc16d -ResourceId https://analysis.windows.net/powerbi/api -UserName $O365Username -Password $O365Password
 
#This example acquire accesstoken by using UserName/Password from contoso.onmicrosoft.com Azure Active Directory for PowerBI service.


#Step 2: Create PSCredential object
$AppCredential= New-Object System.Management.Automation.PSCredential(<UPN>,<Token>)

#Step3: Pass the PSCredential to the EXO V2 module
#Install-Module -Name ExchangeOnlineManagement
Import-Module -Name ExchangeOnlineManagement

Connect-ExchangeOnline -Credential $AppCredential