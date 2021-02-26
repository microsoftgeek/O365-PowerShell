$AdminUsername = "admin@your-domain.onmicrosoft.com" 
$AdminPassword = "YourPassword"
$AdminSecurePassword = ConvertTo-SecureString -String "$AdminPassword" -AsPlainText -Force
$AdminCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $AdminUsername,$AdminSecurePassword

$ExchangeSession = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri "https://outlook.office365.com/powershell-liveid/" -Credential $Admincredential -Authentication "Basic" -AllowRedirection
Import-PSSession $ExchangeSession



$access = "FullAccess"
$mailbox = Get-Mailbox -Identity YourMailbox
$identity = $mailbox.UserPrincipalName
$permissions = Get-MailboxPermission -identity $identity

$users = Import-Csv -Path "C:\path\members.csv" -Delimiter ";" 
foreach($user in $users){
    try{
        $setPermissions = Add-MailboxPermission -Identity $identity -User $user -AccessRights $access
        Write-Host "Successfully added permissions for $user" -ForegroundColor Green
    }catch{
        Write-Host "Failed to add permissions for $user" -ForegroundColor Red
    }
}