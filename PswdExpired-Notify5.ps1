Import-Module ActiveDirectory
 
$Today = Get-Date
$warnDays = 14 # How many days remaining to email from
 
# Email setup
$EmailFrom = "O365User@domain.com"
$SMTPServer = "smtp.office365.com"
$SMTPClient = New-Object Net.Mail.SmtpClient($SmtpServer, 587) 
$SMTPClient.EnableSsl = $true
$SMTPClient.Credentials = New-Object System.Net.NetworkCredential("O365User@domain.com", "Password"); 
 
# Get a list of AD accounts where enables and the password can expire
$ADUsers = Get-ADUser -Filter {Enabled -eq $true  -and PasswordNeverExpires -eq $false } -Properties 'msDS-UserPasswordExpiryTimeComputed', 'mail'
$AlreadyExpiredList = ""
 
# For each account
$Results = foreach( $User in $ADUsers ){
    # Get the expiry date and convert to date time
    $ExpireDate = [datetime]::FromFileTime( $User.'msDS-UserPasswordExpiryTimeComputed' )
    $ExpireDate_String = $ExpireDate.ToString("dd/MM/yyyy h:mm tt") # Format as UK
 
    # Calculate the days remaining
    $daysRmmaining  = New-TimeSpan -Start $Today -End $ExpireDate
    $daysRmmaining = $daysRmmaining.Days
 
    $usersName = $User.Name
 
    # Email users with a remaining count less than or equal $warnDays but also 0 or greater (no expired yet)
    if ($daysRmmaining -le $warnDays -And $daysRmmaining -ge 0)
    {
        # Generate email subjet from days remaining
        if ($daysRmmaining -eq 0)
        {
            $emailSubject = "Your password expires today"
        } else {
            $emailSubject = "Your password expires in $daysRmmaining days"
        }
 
        # Get users email
        if($null -eq $user.mail)
        {
            # The user does not have an email address in AD, alert the IT department
            $sendTo = "ITDept@domain.com"
            $emailBody = "$usersName password expires $ExpireDate_String. But can't email them as their AD mail feild is balnk :-("
        } else {
            # The user has an email address
            $sendTo = $user.mail
 
            $emailBody = "
                $usersName,</br></br>
                Your password expires $ExpireDate_String.</br></br>
 
                It is important that you reset your password ASAP to avoid any disruption.</br></br>
                 
                How do I reset my password.</br>
                1. If you are not at the Head Office connect to the VPN.</br>
                2. While logged on press CTRL + ALT + DELETE and click Change Password.</br>
                3. Enter your current password, enter and confirm a new password that meets the below password policy. Press Enter</br>
                4. Press CTRL + ALT + DELETE and click Lock.</br>
                5. Unlock your computer with your new password</br></br>
                 
                Thank you for your co-operation.</br></br>
                 
                IT Dept</br>
            "
 
           $SMTPMessage = New-Object System.Net.Mail.MailMessage($EmailFrom,$sendTo,$emailSubject,$emailBody)
           $SMTPMessage.IsBodyHTML = $true
           $SMTPClient.Send($SMTPMessage)
        }
    } elseif ($daysRmmaining -lt 0) {
        # Password already expired, add the users details to a list ready for email
        $userMail = $user.mail
        $AlreadyExpiredList = $AlreadyExpiredList + "$usersName, $userMail, $ExpireDate_String</br>"
    }    
}
 
# Send already expired, alert the IT department with the list of people
if ($null -ne $AlreadyExpiredList)
{
    $sendToAlreadyExpired = "ITDept@domain.com"
    $subjectAlreadyExpired = "These users passwords have expired. They may need assistance"
 
    $SMTPMessage = New-Object System.Net.Mail.MailMessage($EmailFrom,$sendToAlreadyExpired,$subjectAlreadyExpired,$AlreadyExpiredList)
    $SMTPMessage.IsBodyHTML = $true
    $SMTPClient.Send($SMTPMessage)
}