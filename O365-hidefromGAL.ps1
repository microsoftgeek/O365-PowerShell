$UserCredential = Get-Credential
$Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://outlook.office365.com/powershell-liveid/ -Credential $UserCredential -Authentication Basic -AllowRedirection
Import-PSSession $Session

##################################################

Get-Mailbox –ResultSize Unlimited | Where {$_.HiddenFromAddressListsEnabled -eq $True} | Select Name, HiddenFromAddressListsEnabled | export-csv c:\temp\hiddenGAL.csv

########################################

Connect-MsolService

Get-MsolRoleMember -RoleObjectId $(Get-MsolRole -RoleName "Company Administrator").ObjectId |
Select-Object -Property DisplayName,EmailAddress,UserPrincipalName | Export-Csv -NoTypeInformation -Path c:\temp\GlobalAdmins2.csv


##################################

$users = import-csv c:\temp\global-admins.csv
 foreach ($user in $users)
{

Set-mailcontact $user.Name -HiddenFromAddressListsEnabled:$false

}
###########################################

$users = import-csv c:\temp\global-admins.csv
foreach ($user in $users){
Set-mailbox $user.EmailAddress –HiddenFromAddressListsEnabled $false
}
############################################

Import-Csv 'C:\temp\Global-Admins2.csv' | ForEach-Object {
$upn = $_."UserPrincipalName"
Set-Mailbox -Identity $upn -HiddenFromAddressListsEnabled $true
}
