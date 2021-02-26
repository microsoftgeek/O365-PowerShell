#The Power of PowerShell

#export E3 guys after filtering 
Get-MsolUser | Where-Object { $_.isLicensed -eq "TRUE" } | Select-Object UserPrincipalName, DisplayName | Export-Csv c:\temp\LicensedUsers.csv -notype


#Connect to O365
$Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://outlook.office365.com/powershell-liveid -Credential (Get-Credential) -Authentication Basic -AllowRedirection

Import-csv c:\temp\LicensedUsers.csv |Foreach{
Get-Mailbox $_.UserPrincipalName | Where-Object { $_.LitigationHoldEnabled -eq $False } | Set-Mailbox -LitigationHoldEnabled $true -LitigationHoldDuration 7000
}