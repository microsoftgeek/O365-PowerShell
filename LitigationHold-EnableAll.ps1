# Connect to Exchange Online
$exo = New-PSSession -ConfigurationName Microsoft.Exchange `
-ConnectionUri https://ps.outlook.com/powershell-liveid `
-Authentication Basic `
-AllowRedirection `
-Credential $(Get-credential)

Import-PSSession $exo

# Get all mailboxes that do not have litigation hold enabled
$mailboxes = Get-Mailbox -ResultSize Unlimited -Filter {RecipientTypeDetails -eq “UserMailbox”} |
Where {$_.LitigationHoldEnabled -ne $true}

# Enable litigation hold
$mailboxes | Set-Mailbox -LitigationHoldEnabled $true

Remove-PSSession $exo