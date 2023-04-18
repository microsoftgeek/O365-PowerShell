#Enable WinRM
Enable-PSRemoting -Force
Set-Item wsman:\localhost\client\trustedhosts *
Restart-Service WinRM



#Install EXO
Install-Module -Name ExchangeOnlineManagement -Verbose -Force
Import-Module ExchangeOnlineManagement -Verbose -Force
Update-Module -Name ExchangeOnlineManagement -Verbose -Force

#Connect to EXO
$UserCredential = Get-Credential
Connect-ExchangeOnline -Credential $UserCredential -ShowProgress $true

#Get User DL
#$Username = "Joe.Fisher@cabinetworksgroup.com"
#$DistributionGroups= Get-DistributionGroup | where { (Get-DistributionGroupMember $_.Name | foreach {$_.PrimarySmtpAddress}) -contains "$Username"}
Get-DistributionGroup | where { (Get-DistributionGroupMember $_.Name | foreach {$_.PrimarySmtpAddress}) -eq "Joe.Fisher@cabinetworksgroup.com"}|fl DisplayName,GroupType,OrganizationalUnit,PrimarySmtpAddress | Export-Csv c:\temp\JF-DLs.csv -NoTypeInformation