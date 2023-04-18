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
$smtpTo = "Cesar.Duran@cabinetworksgroup.com"
$messageSubject = "Your Domain password will expire in 7 days. Please change it as soon as possible."

$messageBody = "Dear Cesar, Your Domain password will expire in 7 days. Please change it as soon as possible.

To change your password, follow the method below:

1. On your Windows computer
	a.	If you are not in the office, logon and connect to VPN. 
	b.	Log onto your computer as usual and make sure you are connected to the internet.
	c.	Press Ctrl-Alt-Del and click on ""Change Password"".
	d.	Fill in your old password and set a new password.  See the password requirements below.
	e.	Press OK to return to your desktop. 

The new password must meet the minimum requirements set forth in our corporate policies including:
	1.	It must be at least 12 characters long.
	2.	It must contain at least one character from 3 of the 4 following groups of characters:
		a.  Uppercase letters (A-Z)
		b.  Lowercase letters (a-z)
		c.  Numbers (0-9)
		d.  Symbols (!@#$%^&*...)
	3.	It cannot match any of your past 24 passwords.
	4.	It cannot contain characters which match 3 or more consecutive characters of your username.
	5.	You cannot change your password more often than once in a 24 hour period.

If you have any questions please contact our Support team at ClientServicesDesk@cabinetworksgroup.com or call us at 888.977.6388

Thanks,
CWGHQ IT Department"

$smtp = New-Object Net.Mail.SmtpClient($smtpServer)
$smtp.Send($smtpFrom,$smtpTo,$messagesubject,$messagebody)