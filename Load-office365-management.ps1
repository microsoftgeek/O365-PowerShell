# https://technet.microsoft.com/en-us/library/dn568015.aspx
# Connect MSOnline admin
$credential = Get-Credential
Import-Module MsOnline
Connect-MsolService -Credential $credential

# Connect to SharePoint online admin
Import-Module Microsoft.Online.SharePoint.PowerShell -DisableNameChecking
Connect-SPOService -Url https://domain-admin.sharepoint.com -credential $credential

# Connect to Skype online admin
# Import-Module SkypeOnlineConnector ---> wouldn't load had to locally load it since the install didn't seem to work
Import-Module "C:\Program Files\Common Files\Skype for Business Online\Modules\SkypeOnlineConnector"
$sfboSession = New-CsOnlineSession -Credential $credential
Import-PSSession $sfboSession

# Connect to Exchange online admin
$exchangeSession = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri "https://outlook.office365.com/powershell-liveid/" -Credential $credential -Authentication "Basic" -AllowRedirection
Import-PSSession $exchangeSession -DisableNameChecking

# Connect to Security and Compliance online admin
# -prefix cc allows you to load both the commands for exchange and security and compliance
# so Get-RoleGroup becomes Get-ccRoleGroup in security and compliance
$ccSession = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://ps.compliance.protection.outlook.com/powershell-liveid/ -Credential $credential -Authentication Basic -AllowRedirection
Import-PSSession $ccSession -Prefix cc

# Close down all sessions
# Remove-PSSession $sfboSession ; Remove-PSSession $exchangeSession ; Remove-PSSession $ccSession ; Disconnect-SPOService