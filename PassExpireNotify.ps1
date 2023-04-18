##Version 1.1 - Edited to change line 77 per SC # 277477 -RC3220


#Please Configure the following variables...
$date = Get-Date -format MMddyyyy
$smtpServer= "emailserver"
$expireindays = 14
$from = "Help Desk <Helpdesk@company.com>"
$logging = "Enabled" #Set to Disabled to Disable Logging
$logFile = "passwordnotification-$date.csv"
$testing = "Disabled" #Set to Disabled to Email Users
$testRecipient = ""
$attachment = "PasswordFAQS.pdf"

#Check Logging Settings
if (($logging) -eq "Enabled")
{
    #Test Log File Path
    $logfilePath = (Test-Path $logFile)
    if (($logFilePath) -ne "True")
    {
        #Create CSV File and Headers
        New-Item $logfile -ItemType File
        Add-Content $logfile "Date,Name,EmailAddress,DaystoExpire,ExpiresOn"
    }
} #End Logging Check

#Get Users From AD who are Enabled, Passwords Expire and are Not Currently Expired
Import-Module ActiveDirectory

$users = get-aduser -filter * -properties Name, GivenName, PasswordNeverExpires, PasswordExpired, PasswordLastSet, EmailAddress |where {$_.Enabled -eq "True"} | where { $_.PasswordNeverExpires -eq $false } | where { $_.passwordexpired -eq $false }
$maxPasswordAge = (Get-ADDefaultDomainPasswordPolicy).MaxPasswordAge

#Process Each User for Password Expiry
foreach ($user in $users)
{
    $Name = (Get-ADUser $user | foreach { $_.GivenName})
    $emailaddress = $user.emailaddress
    $passwordSetDate = (get-aduser $user -properties * | foreach { $_.PasswordLastSet })
    $PasswordPol = (Get-AduserResultantPasswordPolicy $user)
    # Check for Fine Grained Password
    if (($PasswordPol) -ne $null)
    {
        $maxPasswordAge = ($PasswordPol).MaxPasswordAge
    }
  
    $expireson = $passwordsetdate + $maxPasswordAge
    $today = (get-date)
    $daystoexpire = (New-TimeSpan -Start $today -End $Expireson).Days
        
    #Set Greeting based on Number of Days to Expiry

    #Check Number of Days to Expiry
    $messageDays = $daystoexpire

    if (($messageDays) -ge "1")
    {
        $messageDays = "in " + "$daystoexpire" + " days"
    }
    else
    {
        $messageDays = "today."
    }

    #Email Subject Set Here
    $subject="Your network password will expire in $messageDays"
  
    #Email Body Set Here, Note You can use HTML, including Images
    
	$body ="
    Hello $name,
    <p>As a courtesy reminder, your network password will expire on $ExpiresOn.</p>
    <p>To continue to work without disruption, please follow the instructions below to change your password in advance.
	If any issues arise please refer to PasswordFAQS.pdf attachment.</p>
    <p>Thank You,</p>
	<p>Help Desk</p>
    <p><strong>To Reset your Password:</strong></p>
    <p>You can reset your password at any time prior to the scheduled expiration date.</p>
    <p>Preferred Method --- NOT CITIRX</p>
 <ol>
 <li>Press Ctrl + Alt + Del</li>
 <li>Click Change a Password</li>
 <li>Enter your Current (Old) Password</li>
 <li>Enter a New Password</li>
 <li>Confirm the New Password</li>
 <li>Click the Submit arrow in the Confirm Password box</li>
 <li>Click OK to proceed back into your session</li>
 </ol>
    <p>CITRIX USERS</p>
 <ol>
 <li>Click this link: <a href='http://passwordreset/' target='_blank'>http://website/</a></li>
 <li>Click 'here' (in the green box)</li>
 <li>Sign in with your current credentials</li>
 <li>Click the ‘Home’ tab and choose ‘Change My Password’</li>
 <li>Enter a new password in the ‘Password’ and ‘Confirm Password’ fields</li>
 <li>Press SUBMIT</li>
 <li>Click OK (then close the webpage)</li>
 <li>Log Off Current Citrix session</li>
 <li>Log back into a new Citrix session</li>	"
   
    #If Testing Is Enabled - Email Administrator
    if (($testing) -eq "Enabled")
    {
        $emailaddress = $testRecipient
    } 
    
    #End Testing

    #If a user has no email address listed
    if (($emailaddress) -eq $null)
    {
        $emailaddress = $testRecipient    
    }
    #End No Valid Email

    #Send Email Message
	#expires in 7, 5, 3, 2, or 1 days or even Day Of
    if (($daystoexpire -eq "0" -or $daystoexpire -eq "7" -or $daystoexpire -eq "5" -or $daystoexpire -eq "3" -or $daystoexpire -eq "2" -or $daystoexpire -eq "1") -and ($daystoexpire -lt $expireindays))
    {
        #If Logging is Enabled Log Details
        if (($logging) -eq "Enabled")
        {
            Add-Content $logfile "$date,$Name,$emailaddress,$daystoExpire,$expireson" 
        }
        #Send Email Message
        $anonUsername = "anonymous"
        $anonPassword = ConvertTo-SecureString -String "anonymous" -AsPlainText -Force
        $anonCredentials = New-Object System.Management.Automation.PSCredential($anonUsername,$anonPassword)
        Send-Mailmessage -smtpServer $smtpServer -from $from -to $emailaddress -subject $subject -body $body -Attachments $attachment -bodyasHTML -priority High -Credential $anonCredentials 
    } #End Send Message
    
} #End User Processing


#Configure date and send log email
$TimeforLog = (Get-Date -UFormat %m/%d/%y)
#Send-Mailmessage -smtpServer $smtpServer -from $from -to "Michael.Siskind@medmutual.com" -Subject "PW Email Reminder Log $TimeforLog" -Attachments $logfile -Credential $anonCredentials

Move-Item -Path $logFile -Destination UNC HERE