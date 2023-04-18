$ExpireDays = 10
Import-Module ActiveDirectory
$AllUsers = get-aduser -filter * -properties * |where {$_.Enabled -eq "True"} | where { $_.PasswordNeverExpires -eq $false } | where { $_.passwordexpired -eq $false }
foreach ($User in $AllUsers)
{
  $Name = (Get-ADUser $User | foreach { $_.Name})
  $Email = $User.emailaddress
  $PasswdSetDate = (get-aduser $User -properties * | foreach { $_.PasswordLastSet })
  $MaxPasswdAge = (Get-ADDefaultDomainPasswordPolicy).MaxPasswordAge
  $ExpireDate = $PasswdSetDate + $MaxPasswdAge
  $Today = (get-date)
  $DaysToExpire = (New-TimeSpan -Start $Today -End $ExpireDate).Days
  $EmailSubject="Password Expiry Notice - your password expires in $DaystoExpire days"
  $Message="
  Dear $Name,
  <p> Your Password expires in $DaysToExpire days.<br />
  To change your password, Press CTRL+ ALT + DEL together and change Password. <br />
  
  <p><B>Passwords must contain:</B> </p>

a minimum of 1 lower case letter [a-z] and </br />
a minimum of 1 upper case letter [A-Z] and </br />
a minimum of 1 numeric character [0-9] and </br />
a minimum of 1 special character: ~!@#$%^&*()_+={}[]|\;:<>/? </br />



<p>If you do not update your password in $DaysToExpire days, you will not be able to log in, so please make sure you update your password. <br /></p>



<p>If you need any help, contact us via email: helpdesk@example.org, by internal phone 1337. <br /></p>



Sincerely, <br />
  The IT Department. <br />
  </p>"
  
    

<#authentication method
# smtp server
$emailSmtpServer = ""
$emailSmtpServerPort = "587"
$emailSmtpUser = ""
$emailSmtpPass = ""
# recipient 
$emailFrom = ""
$emailTo = $Email
# message
$emailMessage = New-Object System.Net.Mail.MailMessage( $emailFrom , $emailTo )
$emailMessage.Subject = $EmailSubject
$emailMessage.IsBodyHtml = $true
$emailMessage.Body = $Message
#client 
$SMTPClient = New-Object System.Net.Mail.SmtpClient( $emailSmtpServer , $emailSmtpServerPort )
$SMTPClient.EnableSsl = $False #if SSL is enable set as True
$SMTPClient.Credentials = New-Object System.Net.NetworkCredential( $emailSmtpUser , $emailSmtpPass );
$SMTPClient.Send( $emailMessage )
#>

  } 

  #>


  ##### if added SMTP replay remove all # below the line ####


$smtp = "Exchange-Server" 
 
 $to = "$Email" 
 
$from = "Sender mail" 
 
$subject = "$EmailSubject"  
 
$body = "$Message" 
  
 
#### Now send the email using \> Send-MailMessage  
 
 send-MailMessage -SmtpServer $smtp -To $to -From $from -Subject $subject -Body $body -BodyAsHtml 