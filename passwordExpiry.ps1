function passwordExpiry(){
    $Report = @()
    $Today = Get-Date
    $Users = Get-ADUser -Filter * -Properties passwordlastset,UserPrincipalName,PasswordNeverExpires | Sort-Object Name | Select-Object Name,passwordlastset,UserPrincipalName,PasswordNeverExpires
