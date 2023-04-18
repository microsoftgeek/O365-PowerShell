#***PowerShell needs to have TLS 1.2 enabled in order to run EXO v2***#
#Run this in PowerShell:   
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

#Install EXO
Install-Module -Name ExchangeOnlineManagement -Verbose -Force
Import-Module ExchangeOnlineManagement -Verbose -Force
Update-Module -Name ExchangeOnlineManagement -Verbose -Force

#Connect to EXO
$UserCredential = Get-Credential
Connect-ExchangeOnline -Credential $UserCredential -ShowProgress $true

#Connect to Compliance
Connect-IPPSSession -UserPrincipalName Cesar.Duran-DA@cabinetworksgroup.com

#Get and Delete Compliance Searches
Get-ComplianceSearch -Identity "RESPOND ASAP" | Format-List

New-ComplianceSearchAction -SearchName "RESPOND ASAP" -Purge -PurgeType HardDelete -Force
New-ComplianceSearchAction -SearchName "RESPOND ASAP - ALL" -Purge -PurgeType HardDelete -Force
New-ComplianceSearchAction -SearchName "Due Invoice Payment" -Purge -PurgeType HardDelete -Force