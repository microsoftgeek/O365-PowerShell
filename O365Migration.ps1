Write-Output "$HR Enterprise Support O365 Migration Script

##########################################################################################
#
#                  *Enterprise Support O365 Migration Script* 
#                                                                                
# Created by Cesar Duran (Jedi Master)                                                                                        
# Version:1.0                                                                                                                                       
#                                                                                                                                                                                                                                                              
# O365 Migration Tasks:
# 1) Connect to O365
# 2) Migrate Exchange mailbox to O365
# 3) Check Migration Status
# 4) Enable Litigation Hold on O365 Mailbox
# 5) Disable the O365 Mailbox Clutter feature
# 6) Assign O365 Licenses
#                                                                                                                                                                                                                                                                                                                                                                                    
#                                                                                                                                                                                                          
###########################################################################################

$HR"

# Line delimiter
$HR = "`n{0}`n" -f ('='*20)


##################################################
Write-Output "$HR CONNECT TO OFFICE 365 $HR"
# Connecting to O365 Administration

$UserCredential = Get-Credential
$Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://outlook.office365.com/powershell-liveid/ -Credential $UserCredential -Authentication Basic -AllowRedirection
Import-PSSession $Session

#End of connecting to O365

######################################
Write-Output "$HR 5 SECOND PAUSE $HR"
# 5sec Pause

$Timeout = 30
$timer = [Diagnostics.Stopwatch]::StartNew()
while (($timer.Elapsed.TotalSeconds -lt $Timeout)) {
Start-Sleep -Seconds 1
    Write-Verbose -Message "Still waiting for action to complete after [$totalSecs] seconds..."
}
$timer.Stop()
# End of 5 seconds


##############################################
Write-Output "$HR MIGRATE MAILBOX TO O365 $HR"
#Create the move requests

#Set your AD credentials to a variable.
$RemoteCredential = Get-credential

Import-csv .\NewHire10.csv | foreach { 

new-moverequest -Identity $_.EmailAddress -Remote -Remotehostname hybrid.cdirad.com -Targetdeliverydomain cdirad.mail.onmicrosoft.com -Baditemlimit 50 -LargeItemLimit 10 -AcceptLargeDataLoss -RemoteCredential $RemoteCredential

}
#End of migration mailbox moves


######################################
Write-Output "$HR 3 MINUTE PAUSE $HR"
# 90sec Pause

$Timeout = 180
$timer = [Diagnostics.Stopwatch]::StartNew()
while (($timer.Elapsed.TotalSeconds -lt $Timeout)) {
Start-Sleep -Seconds 1
    Write-Verbose -Message "Still waiting for action to complete after [$totalSecs] seconds..."
}
$timer.Stop()
# End of 3 minutes

###################################################
Write-Output "$HR ALMOST THERE, HANG ON!!!

##########################################################################################
#
#              *PATIENCE YOU MUST HAVE, MY YOUNG PADAWAN - YODA*
#
#                                                                                                                                                                                                                                                                                                                                                                                                                              
#                                                                                                                                                                                                          
###########################################################################################

$HR"


######################################
Write-Output "$HR 1 MINUTE PAUSE $HR"
# 90sec Pause

$Timeout = 60
$timer = [Diagnostics.Stopwatch]::StartNew()
while (($timer.Elapsed.TotalSeconds -lt $Timeout)) {
Start-Sleep -Seconds 1
    Write-Verbose -Message "Still waiting for action to complete after [$totalSecs] seconds..."
}
$timer.Stop()
# End of 1 minute


####################################################
Write-Output "$HR O365 MAILBOX MIGRATION STATUS $HR"
#Check on the status of the moves

Import-csv .\NewHire10.csv | foreach { 
Get-moverequeststatistics $_.EmailAddress 

}
#End of O365 mailbox status check


#####################################
Write-Output "$HR 30 SECOND PAUSE $HR"
# 90sec Pause

$Timeout = 30
$timer = [Diagnostics.Stopwatch]::StartNew()
while (($timer.Elapsed.TotalSeconds -lt $Timeout)) {
Start-Sleep -Seconds 1
    Write-Verbose -Message "Still waiting for action to complete after [$totalSecs] seconds..."
}
$timer.Stop()
# End of 30 seconds


######################################
Write-Output "$HR APPLY O365 LICENSES $HR"
#user the following string to set licenses

.\LicenseUsers.ps1 -userfile .\NewHire10.csv

#End of applying O365 licenses


######################################
Write-Output "$HR 1 MINUTE PAUSE $HR"
# 90sec Pause

$Timeout = 60
$timer = [Diagnostics.Stopwatch]::StartNew()
while (($timer.Elapsed.TotalSeconds -lt $Timeout)) {
Start-Sleep -Seconds 1
    Write-Verbose -Message "Still waiting for action to complete after [$totalSecs] seconds..."
}
$timer.Stop()
# End of 60 seconds


##################################################
Write-Output "$HR ENABLE O365 LITIGATION HOLD $HR"
#When moves are complete, set litigation settings

Import-csv .\NewHire10.csv | foreach { 
set-mailbox $_.EmailAddress –litigationholdenabled $true 

}
#End of enable litigation hold



######################################
Write-Output "$HR 1 MINUTE PAUSE $HR"
# 90sec Pause

$Timeout = 60
$timer = [Diagnostics.Stopwatch]::StartNew()
while (($timer.Elapsed.TotalSeconds -lt $Timeout)) {
Start-Sleep -Seconds 1
    Write-Verbose -Message "Still waiting for action to complete after [$totalSecs] seconds..."
}
$timer.Stop()
# End of 60 seconds



##################################################
Write-Output "$HR DISABE O365 CLUTTER FEATURE $HR"
#Turn off Clutter folder

Import-csv .\NewHire10.csv | foreach { 
Set-Clutter -Identity $_.EmailAddress -Enable $false 

}
#End of disabling clutter feature



#####################################
Write-Output "$HR 5 SECOND PAUSE $HR"
# 90sec Pause

$Timeout = 5
$timer = [Diagnostics.Stopwatch]::StartNew()
while (($timer.Elapsed.TotalSeconds -lt $Timeout)) {
Start-Sleep -Seconds 1
    Write-Verbose -Message "Still waiting for action to complete after [$totalSecs] seconds..."
}
$timer.Stop()
# End of 5 second pause



##############################################
Write-Output "$HR REMOVE THE PSSESSION $HR"
#When done close your remote session to avoid being throttled and locked out.

Get-pssession | remove-pssession



######################################
Write-Output "$HR 5 SECOND PAUSE $HR"
# 90sec Pause

$Timeout = 5
$timer = [Diagnostics.Stopwatch]::StartNew()
while (($timer.Elapsed.TotalSeconds -lt $Timeout)) {
Start-Sleep -Seconds 1
    Write-Verbose -Message "Still waiting for action to complete after [$totalSecs] seconds..."
}
$timer.Stop()
# End of 5 seconds



###################################################
Write-Output "$HR THE END, HAVE A NICE DAY!!!

##########################################################################################
#
#              *POWERFUL YOU HAVE BECOME, THE DARK SIDE I SENSE IN YOU - YODA*
#
#                                                                                                                                                                                                                                                                                                                                                                                                                              
#                                                                                                                                                                                                          
###########################################################################################

$HR"
