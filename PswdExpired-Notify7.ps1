#################################################################################################################
#
# Original Robert Pearman v1.4 Passowrd Change Notification
# – Adapted to support O365 SendAS Shared Mailbox
# Script to Automate Email Reminders when Users Passwords due to Expire using O365 Shared Mailbox.
#
# Requires:
# Windows PowerShell Module for Active Directory
# Azure AD Application registration with MS Graph Application Mail.Send permission
#
#
##################################################################################################################
# Please Configure the following variables….
$expireindays = 21
$logging = “Enabled” # Set to Disabled to Disable Logging
$logFile = “” # ie. c:mylog.csv
$testing = “Enabled” # Set to Disabled to Email Users
$testRecipient = ”
$clientId = ” # App registration ID used to send on behalf of shared mailbox
$clientSecret = (Import-Clixml -Path $PSScriptRootSendEmailSecret.ps1.credential).GetNetworkCredential().Password #Client Secret credential file
$tenantName = ” #TenantName
$SendEmailAccount = ” #SharedMailbox name
$resource = ‘https://graph.microsoft.com’ #Graph Endpoint https://graph.microsoft.com or https://graph.microsoft.us or https://dod-graph.microsoft.us
#
###################################################################################################################
$ReqTokenBody = @{
Grant_Type = “client_credentials”
Scope = “$($resource)/.default”
client_Id = $clientID
Client_Secret = $clientSecret
}
Try {
$params = @{
Uri = “https://login.microsoftonline.com/$TenantName/oauth2/v2.0/token”
Method = “POST”
ErrorAction = “Stop”
}
$TokenResponse = Invoke-RestMethod @params -Body $ReqTokenBody

if ($TokenResponse) {
# Check Logging Settings
if (($logging) -eq “Enabled”)
{
# Test Log File Path
$logfilePath = (Test-Path $logFile)
if (($logFilePath) -ne “True”)
{
# Create CSV File and Headers
New-Item $logfile -ItemType File
Add-Content $logfile “Date,Name,EmailAddress,DaystoExpire,ExpiresOn,Notified”
}
} # End Logging Check

# System Settings
$textEncoding = [System.Text.Encoding]::UTF8
$date = Get-Date -format ddMMyyyy
# End System Settings

# Get Users From AD who are Enabled, Passwords Expire and are Not Currently Expired
Import-Module ActiveDirectory
$users = get-aduser -filter * -properties Name, PasswordNeverExpires, PasswordExpired, PasswordLastSet, EmailAddress |where {$_.Enabled -eq “True”} | where { $_.PasswordNeverExpires -eq $false } | where { $_.passwordexpired -eq $false }
$DefaultmaxPasswordAge = (Get-ADDefaultDomainPasswordPolicy).MaxPasswordAge

# Process Each User for Password Expiry
foreach ($user in $users)
{
$Name = $user.Name
$emailaddress = $user.emailaddress
$passwordSetDate = $user.PasswordLastSet
$PasswordPol = (Get-AduserResultantPasswordPolicy $user)
$sent = “” # Reset Sent Flag
# Check for Fine Grained Password
if (($PasswordPol) -ne $null)
{
$maxPasswordAge = ($PasswordPol).MaxPasswordAge
}
else
{
# No FGP set to Domain Default
$maxPasswordAge = $DefaultmaxPasswordAge
}

$expireson = $passwordsetdate + $maxPasswordAge
$today = (get-date)
$daystoexpire = (New-TimeSpan -Start $today -End $Expireson).Days

# Set Greeting based on Number of Days to Expiry.

# Check Number of Days to Expiry
$messageDays = $daystoexpire

if (($messageDays) -gt “1”)
{
$messageDays = “in ” + “$daystoexpire” + ” days.”
}
else
{
$messageDays = “today.”
}
# If Testing Is Enabled – Email Administrator
if (($testing) -eq “Enabled”)
{
$emailaddress = $testRecipient
} # End Testing

# If a user has no email address listed
if (($emailaddress) -eq $null)
{
$emailaddress = $testRecipient
}# End No Valid Email

# Email Subject Set Here
$subject=”Your password will expire $messageDays”

# Email Body Set Here, Note You can use HTML.
$body = @”
{
“Message”: {
“Subject”: “$($subject)”,
“importance”:”High”,
“Body”: {
“ContentType”: “HTML”,
“Content”: “<p>Dear $($name),</p>
<p> Your Password will expire $($messageDays)<br>
To change your password on a PC press CTRL ALT Delete and choose Change Password <br>
<p>Thanks, <br>
</P>”
},
“ToRecipients”: [
{
“EmailAddress”: {
“Address”: “$($emailaddress)”
}
}
]
},
“SaveToSentItems”: “false”,
“isDraft”: “false”
}
“@

# Send Email Message
if (($daystoexpire -ge “0”) -and ($daystoexpire -lt $expireindays))
{
$sent = “Yes”
# If Logging is Enabled Log Details
if (($logging) -eq “Enabled”)
{
Add-Content $logfile “$date,$Name,$emailaddress,$daystoExpire,$expireson,$sent”
}
# Send Email Message
$apiUrl = “$resource/v1.0/users/$SendEmailAccount/sendMail”
Invoke-RestMethod -Headers @{Authorization = “Bearer $($Tokenresponse.access_token)”} -Uri $apiUrl -Body $Body -Method Post -ContentType ‘application/json’

} # End Send Message
else # Log Non Expiring Password
{
$sent = “No”
# If Logging is Enabled Log Details
if (($logging) -eq “Enabled”)
{
Add-Content $logfile “$date,$Name,$emailaddress,$daystoExpire,$expireson,$sent”
}
}
}

} # End User Processing

} catch {
[System.ApplicationException]::new(“Failed to aquire token”)
}