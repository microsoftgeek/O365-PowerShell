#Login to Office 365
$UserName = "admin@M365.onmicrosoft.com" 
$Password = ConvertTo-SecureString "xxxxxxxxxxxxx" -AsPlainText -Force
$credential = New-Object System.Management.Automation.PsCredential($UserName,$Password)

Import-Module MSOnline
Connect-MsolService -Credential $Credential

### Exchange Online v2
Import-Module ExchangeOnlineManagement

# Login to Exchange Online with MFA Enabled with EXO v2
Connect-ExchangeOnline -UserPrincipalName $UserName -ShowProgress $true

#Connect to Security & Compliance Center
Connect-IPPSSession -UserPrincipalName $UserName

##Add Admin Groups
Add-RoleGroupMember "eDiscoveryManager" -member admin@aventis.dev
Add-RoleGroupMember "ComplianceAdministrator" -member admin@aventis.dev

#New-ComplianceSearch
$Name = "Email from kwyong@aventis.com.my"
New-ComplianceSearch -Name $Name -ExchangeLocation AllanD@Aventis.dev -ContentMatchQuery "from:kwyong@aventis.com.my"


#Start Compliance Search and verify the result
Start-ComplianceSearch -Identity $Name

# Verify the ComplianceSeach is completed successfully
Get-ComplianceSearch $Name

#Name                             RunBy             JobEndTime           Status   
#----                             -----             ----------           ------   
#Email from kwyong@aventis.com.my MOD Administrator 23/1/2021 1:47:17 AM Completed

# Detail information 
Get-ComplianceSearch $Name | Select Name, ContentMatchQuery, Items, SuccessResults

#Name                             ContentMatchQuery          Items SuccessResults                                                   
#----                             -----------------          ----- --------------                                                   
#Email from kwyong@aventis.com.my from:kwyong@aventis.com.my     2 {Location: AllanD@aventis.dev, Item count: 2, Total size: 188826}

##Delete Email Items
New-ComplianceSearchAction -SearchName $Name -Purge -PurgeType SoftDelete -Force
New-ComplianceSearchAction -SearchName $Name -Purge -PurgeType HardDelete -Force