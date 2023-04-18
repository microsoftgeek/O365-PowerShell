#
#.SYNOPSIS
#Sends SMTP email via the Hub Transport server
#
#.EXAMPLE
#.Send-Email.ps1 -To "administrator@exchangeserverpro.net" -Subject "Test email" -Body "This is a test"
#

param(
[string]$to,
[string]$subject,
[string]$body
)

$smtpServer = "AWSHQSMTP02.cabinetworksgroup.net"
$smtpFrom = "cwg-admin@cabinetworksgroup.com"
$smtpTo = $to
$messageSubject = $subject
$messageBody = $body

$smtp = New-Object Net.Mail.SmtpClient($smtpServer)
$smtp.Send($smtpFrom,$smtpTo,$messagesubject,$messagebody)