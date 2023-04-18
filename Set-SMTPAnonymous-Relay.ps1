#Get Connector
Get-ReceiveConnector

#Issue the following PowerShell command to create and configure the connector:
#Create a new Front End receive connector called "P365 Anonymous Relay"
New-ReceiveConnector -Name "P365 Anonymous Relay" `
-TransportRole FrontendTransport -Custom -Bindings 0.0.0.0:25 `
-RemoteIpRanges 192.168.12.5, 192.168.20.0/24


#Configure "P365 Anonymous Relay" to be used anonymously
Set-ReceiveConnector "P365 Anonymous Relay" -PermissionGroups AnonymousUsers
Get-ReceiveConnector "P365 Anonymous Relay" | Add-ADPermission -User "NT AUTHORITY\ANONYMOUS LOGON" `
-ExtendedRights "Ms-Exch-SMTP-Accept-Any-Recipient"



#Configure "P365 Anonymous Relay" as externally secured
Set-ReceiveConnector "P365 Anonymous Relay" -AuthMechanism ExternalAuthoritative `
-PermissionGroups ExchangeServers



#Below is the PowerShell output for the above commands:
#Create a new Front End receive connector called "P365 Anonymous Relay"
New-ReceiveConnector -Name "P365 Anonymous Relay" `
>> -TransportRole FrontendTransport -Custom -Bindings 0.0.0.0:25 `
>> -RemoteIpRanges 192.168.12.5, 192.168.20.0/24


#Configure "P365 Anonymous Relay" to be used anonymously
Set-ReceiveConnector "P365 Anonymous Relay" -PermissionGroups AnonymousUsers
Get-ReceiveConnector "P365 Anonymous Relay" | Add-ADPermission -User "NT AUTHORITY\ANONYMOUS LOGON" `
>> -ExtendedRights "Ms-Exch-SMTP-Accept-Any-Recipient"


#Configure "P365 Anonymous Relay" as externally secured
Set-ReceiveConnector "P365 Anonymous Relay" -AuthMechanism ExternalAuthoritative `
>> -PermissionGroups ExchangeServers


#Send MailMessage
Send-MailMessage -SmtpServer mail.practical365lab.com `
-From ‘administrator@practical365lab.com’ -To ‘nicolasblank@gmail.com’ ‘
-Subject ‘Test Email’ -Port 25