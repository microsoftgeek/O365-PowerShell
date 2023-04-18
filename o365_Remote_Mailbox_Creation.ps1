#Requires -Version 3

<#
.SYNOPSIS
	This script scans for recently created accounts and creates an o365 mailbox based on customattribute1.

.DESCRIPTION    
    Account Requirements
        Required Groups/Credentials:
        -Domain Admin 
        -O365 Admin

    Execution Method(s)
        -Manual
        -Scheduled Task
.NOTES
    Created by:  Jared Orzechowski 
.EXAMPLE
	PS> .\o365_RemoteMailboxCreation
#>

$DebugPreference = "Continue"

## Misc Script settings
$domain = "polarisstage.com"
$defaultMailDomain = "polarisstgdmz.com"
$userSearchBase = "DC=polarisstage,DC=com"
$entAccountSkuId = "polarisstage:ENTERPRISEPACK"  ## This is required since it can vary in different environments
$exchAccountSkuId = "polarisstage:EXCHANGEENTERPRISE"
$minLicenseQty = 1 ## Only run if this many licenses are available (eg 1 to use all any available license) or -9999 to ignore
$reportFile = "c:\scripts\o365_MailNewUsers\newusers.csv"
$mailFormat = "firstlast"  ## either firstlast or username

#If necessary append this to the samaccountname when creating the remoterouting address to ensure unique beteween additional domains, IE _tapww
$routingAddressAppend = "" 

#Licenses to assign to user/exchange types
$userLicenseGroup = "LIC_AZU_o365_Ent_E3_base"
$exchangeLicenseGroup = "LIC_AZU_XCHOnline_Plan2_allfeatures"

## Support group to add to shared/resuorce mailboxes
$supportGroup = "Polaris_POL_WWSD_ExchangeAdministration"

## Room Settings
$roomAutomateProcessing = "AutoAccept"
$roomBookingWindowInDays = 400 
$roomConflictPercentageAllowed = 40 
$roomMaximumConflictInstances = 15 
$roomDeleteComments = $true 
$roomRemovePrivateProperty = $true 
$roomDeleteSubject = $true 
$roomAddOrganizerToSubject = $true
#Old setting:  -DeleteComments $False -RemovePrivateProperty $False  -DeleteSubject $False -AddOrganizerToSubject $False

## Hardcoded variables, 
$O365PSURI = "https://ps.outlook.com/PowerShell/"
$O365Username = "svcdir01@polarisstage.com"
$O365Password = Get-Content c:\scripts\o365_Login\o365_svcdir01.pwd | ConvertTo-SecureString
$O365Creds = New-Object System.Management.Automation.PSCredential($O365Username,$O365Password)
$OnPremPSURI = "https://mpl1stgxch016.polarisstage.com/PowerShell/"
$OnPremCreds = New-Object System.Management.Automation.PSCredential($O365Username,$O365Password)

## Log settings
$date = get-date -format MMdyyyyHHmm
$logPath = $PSScriptRoot + "\log"
$logName = $date + "_Creation.log"
$sFullPath = Join-Path -Path $logPath -ChildPath $logName
[int]$logRetention = 14

##
## No need to edit below this line
##

## Misc (no need to modify)
$dc = get-addomaincontroller -Discover -DomainName $domain | ForEach-Object { $_.HostName }
$currentUser = $env:USERDOMAIN + "\" + $env:USERNAME
$abortTimerMax = 120 ## Used for how many times to run mailbox wait loop

## Check for necessary modules
if (!(Get-Module -ListAvailable ActiveDirectory)) {
    write-host "Missing RSAT, please install before running." -ForegroundColor Red
    exit 1
} else {
    Import-Module ActiveDirectory
}

if (!(Get-Module -ListAvailable MSOnline)) {
    write-host "Missing MSOnline, please install before running." -ForegroundColor Red
    exit 1
} else {
    Import-Module MSOnline
}

if (!($OnPremCreds)) {
    $OnPremCreds = Get-Credential -Message "Enter on-prem Exchange admin credentials."
}

if (!($O365Creds)) {
    $O365Creds = Get-Credential -Message "Enter o365 tenant admin credentials."
}

Function Log-Start {
   
    ## Check if log folder exists
    If (!(Test-Path -Path $logPath) ) {
        New-Item -Path $logPath –ItemType Directory | Out-Null
    }

    ## Make sure current user can edit logpath
    $Acl = Get-Acl "$logPath"
    $Ar = New-Object  system.security.accesscontrol.filesystemaccessrule("$currentUser", "FullControl","ContainerInherit,ObjectInherit","None","Allow")
    $Acl.SetAccessRule($Ar)
    Set-Acl "$logPath" $Acl

    ## Check if log file exists and delete if it does
    If ( (Test-Path -Path $sFullPath) ) {
        Remove-Item -Path $sFullPath -Force
    }

    ## Create file and start logging
    New-Item -Path $sFullPath –ItemType File -Force | Out-Null

    #Final log check
    If(!(Test-Path -Path $sFullPath)){
        Write-Host "Could not create log, exiting.." -ForegroundColor Red
        exit 1
    }

    Add-Content -Path $sFullPath -Value "***************************************************************************************************"
    Add-Content -Path $sFullPath -Value "Started processing at [$(Get-Date -Format g)]."
    Add-Content -Path $sFullPath -Value "***************************************************************************************************"
    Add-Content -Path $sFullPath -Value ""
  
    ## Write to screen for debug mode
    Write-Debug "***************************************************************************************************"
    Write-Debug "Started processing at [$([DateTime]::Now)]."
    Write-Debug "***************************************************************************************************"
    Write-Debug ""
}

Function Log-Write {
    
  [CmdletBinding()]
  
  Param ([Parameter(Mandatory=$true)][string]$LineValue)
  
  Process{
    Add-Content -Path $sFullPath -Value "[$(Get-Date -Format g)] $LineValue"
  
    ## Write to screen for debug mode
    Write-Debug $LineValue
  }
}

Function Log-Finish {
    Add-Content -Path $sFullPath -Value ""
    Add-Content -Path $sFullPath -Value "***************************************************************************************************"
    Add-Content -Path $sFullPath -Value "Finished processing at [$(Get-Date -Format g)]."
    Add-Content -Path $sFullPath -Value "***************************************************************************************************"
  
    ## Write to screen for debug mode
    Write-Debug ""
    Write-Debug "***************************************************************************************************"
    Write-Debug "Finished processing at [$(Get-Date -Format g)]."
    Write-Debug "***************************************************************************************************"
}

## Initialize log file
Log-Start

## Establish sessions
$OnPrem = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri $OnPremPSURI -Credential $OnPremCreds -Authentication Basic -WarningAction SilentlyContinue -ErrorAction Stop
Import-PSSession $OnPrem -Prefix OnPrem -AllowClobber -ErrorAction Stop | Out-Null

$O365 = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri $O365PSURI -Credential $O365Creds -Authentication Basic -AllowRedirection -WarningAction SilentlyContinue -ErrorAction Stop
Import-PSSession $O365 -Prefix O365 -AllowClobber -ErrorAction Stop | Out-Null

if (-not $OnPrem -and -not $O365) {
    Log-Write -LineValue "Session error, cleaning up and exiting."
    Remove-PSSession $OnPrem -ErrorAction SilentlyContinue | Out-Null
    Remove-PSSession $O365 -ErrorAction SilentlyContinue | Out-Null
    exit 1
}

Connect-MSOLService -credential $O365Creds -ErrorAction Stop | Out-Null
$tenantDomain = Get-MsolDomain  | Where-Object { $_.Name -like "*.mail.onmicrosoft.com" } | ForEach-Object Name
$msolDomains = Get-MsolDomain | Select-Object -expandproperty Name

## Get new user list and all the properties we need (you have to manually select exch properties)
$adUsers = Get-ADUser -Server $dc -SearchBase $userSearchBase -Filter { ((msExchMailboxGuid -notlike "*" -and msExchUMDtmfMap -notlike "*" -and msExchRecipientDisplayType -notlike "*" -and Enabled -eq "True" -and (extensionAttribute1 -eq "User" -or extensionAttribute1 -eq "Shared" -or extensionAttribute1 -like "Exchange*" -or extensionAttribute1 -eq "Room" -or extensionAttribute1 -eq "Equipment" -or extensionAttribute1 -eq "SMTPrelay")) -or (extensionAttribute2 -eq "Processing")) } -Properties * -ResultSetSize 60 | Select-Object Name, GivenName, Surname, samAccountName, extensionAttribute1, extensionAttribute2, extensionAttribute3, proxyAddresses, targetAddress, msExchRecipientDisplayType, msExchRecipientTypeDetails, mail, userPrincipalName, DistinguishedName

if ($adUsers) {
    Log-Write -LineValue "Found $($adUsers.samAccountName.count) user(s).."
} else {
    Log-Write -LineValue "No users found."
}

## Collect list of UPNs already in O365 for checking if user exists in O365
$msolUsers = Get-MsolUser -All | Select-Object -expandproperty userPrincipalName

## Process users
:main foreach ($adUser in $adUsers) {

    ## Update extensionAttribute2 to show account is being processed - we will remove at the end
    Set-ADUser -Server $dc -Identity $adUser.samAccountName -Replace @{extensionAttribute2="Processing"} -Credential $OnPremCreds

    ## Check for null attribute otherwise you will get null pointer exceptions if left null
    if (!($adUser.extensionAttribute1)) { $adUser.extensionAttribute1 = "Empty" }

    switch -regex ($adUser.extensionAttribute1.ToLower()) {
       
       ## Main user type with added checks for alternative email types (apex, proarmor, etc)
        "\buser" { Log-Write -LineValue "Processing $($adUser.Name) as $($adUser.extensionAttribute1.ToLower()).."
            
            ## Validate user requirements
            if ($adUser.extensionAttribute2 -eq "SetupComplete") {
                Log-Write -LineValue "$($adUser.Name) validation failed or already migrated, skipping.."
            } else {
                  
                ## Lets make sure we have licenses available
                $licEnterprise = Get-MsolAccountSku | Where-Object { $_.AccountSkuId -like $entAccountSkuId } | Select-Object *
                $qtyEnterprise = $licEnterprise.ActiveUnits - $licEnterprise.ConsumedUnits
                if ($qtyEnterprise -ge $minLicenseQty) {
                    
                    ## We have licenses, proceed
                    Log-Write -LineValue "Current o365 licenses available: $qtyEnterprise"
                    
                    ## Check if user exists in o365 yet (user has to sync to o365 prior to enabling remote mailbox)
                    if ($msolUsers -contains $adUser.userPrincipalName) {
                        ## Set usage location
                        Set-MsolUser -UserPrincipalName $adUser.userPrincipalName -UsageLocation US

                        ## If account was partially processed dont try to recreate the mailbox since it will exit loop on failure
                        if (Get-O365Mailbox $adUser.userPrincipalName -ErrorAction SilentlyContinue  | Select-Object * ) {
                            Log-Write -LineValue "Skipping mailbox setup for $($adUser.Name) as mailbox already exists."
                        } else {
                            ##User is in o365 and we have licenses available so lets enable remote mailbox to configure exch properties (hyrbid only)
                            Log-Write -LineValue "Enabling remote mailbox for $($adUser.Name)"
                            Try {
                                Enable-OnPremRemoteMailbox -Identity $adUser.userPrincipalName -RemoteRoutingAddress "$($adUser.samAccountName)$($routingAddressAppend)@$tenantDomain" -ErrorAction Stop | Out-Null
                            } catch {
                                Log-Write -LineValue "Couldn't enable remote mailbox, aborting: $($Error[0])"
                                Break main
                            }

                            ## After remote mailbox command we need to trigger an ADSync to create the mailbox
                            Log-Write -LineValue "Starting ADSync Delta to begin mailbox creation.."
                            if(!(Get-ADSyncScheduler | Select-Object -expandproperty synccycleinprogress)) {
                                Start-ADSyncSyncCycle -PolicyType Delta -ErrorAction SilentlyContinue | Out-Null
                            } else {
                                Log-Write -LineValue "ADSync already in progress, skipping ADSync trigger.."
                            }

                            ## Lets wait for mailbox creation
                            $abortTimer = 0
                            do {
                                $abortTimer++
                                Log-Write -LineValue "Waiting for O365 to create mailbox for user $($adUser.Name).. [$($abortTimer)] of [$($abortTimerMax)]"
                                $userO365Mailbox = Get-O365Mailbox $adUser.userPrincipalName -ErrorAction SilentlyContinue  | Select-Object * 
                                Start-Sleep 60
                                if ($abortTimer -ge $abortTimerMax) {
                                    Log-Write -LineValue "Mailbox wait abort timer hit, aborting.."
                                    Break main
                                }
                            }
                            While ($null -eq $userO365Mailbox)
                        }

                        ## Custom Email and SIP Address Configuration - must run after enable-remotemailbox so that mail attributes are populated
                        ## Ignore extensionAttribute3 if a default domain was entered as it would fail trying to add a record that already exists
                        if ($adUser.extensionAttribute3 -and $adUser.extensionAttribute3 -notmatch $defaultMailDomain) {
                            Log-Write -LineValue "extensionAttribute3 is configured, validating.."

                            if ($msolDomains -contains $adUser.extensionAttribute3) {
                                    Log-Write -LineValue "$($adUser.extensionAttribute3) is valid msoldomain, configuring new mail address.."
                                    
                                    ## Custom domain overwrite section
                                    if ($adUser.extensionAttribute3 -match "4wheelparts.com") { 
                                        Set-ADUser -Server $dc -Identity $adUser.samAccountName -Replace @{extensionAttribute3="4wp.com"} -Credential $OnPremCreds
                                        $adUser.extensionAttribute3 = "4wp.com"
                                    }
                                    ## End overwrite section

                                    if ($mailFormat -eq "firstlast") {
                                        $emailAlias = $adUser.GivenName + "." + $adUser.Surname
                                    } else {
                                        $emailAlias = $adUser.samAccountName
                                    }
                                   
                                    ## Email assignment validation
                                    $c = 0
                                    do {
                                       if ($c -eq 0) {
                                           $newEmail = $emailAlias + "@" + $adUser.extensionAttribute3
                                           $SMTPAddress = "SMTP:" + $newEmail
                                       } else {
                                           $newEmail = $emailAlias + $c + "@" + $adUser.extensionAttribute3
                                           $SMTPAddress = "SMTP:" + $newEmail
                                       }
                                       $validEmail = Get-ADUser -Server $dc -SearchBase $userSearchBase -Filter {(proxyAddresses -eq $SMTPAddress)}
                                       Log-Write -LineValue "Checking $newEmail availability.."
                                       $c++
                                    } while ($validEmail) 
                                    Log-Write -LineValue "Configuring new email as $($newEmail).."

                                    ## Move current primary to secondary
                                    foreach ($proxyaddress in (get-aduser -server $dc -Filter ('userPrincipalName -eq "' + $adUser.userPrincipalName + '"') -Properties proxyAddresses | Select-Object -ExpandProperty proxyAddresses)) {
                                        if ($proxyaddress -cmatch "SMTP:") {
                                            Log-Write -LineValue "Setting $($proxyaddress) to $($proxyaddress.ToLower()).."
                                            Set-ADUser -Server $dc -Identity $adUser.samAccountName -Remove @{proxyAddresses="$($proxyaddress)"} -Credential $OnPremCreds
                                            Set-ADUser -Server $dc -Identity $adUser.samAccountName -Add @{proxyAddresses="$($proxyaddress.ToLower())"} -Credential $OnPremCreds
                                        }
                                    }

                                    ## Add users new email
                                    Log-Write -LineValue "Setting mail attribute to $($newEmail).."
                                    Set-ADUser -Server $dc -Identity $adUser.samAccountName -Replace @{mail=$newEmail} -Credential $OnPremCreds
                                    Log-Write -LineValue "Adding new primary proxyaddress $($SMTPAddress).."
                                    Set-ADUser -Server $dc -Identity $adUser.samAccountName -Add @{proxyAddresses=$SMTPAddress} -Credential $OnPremCreds

                                    if ($adUser.extensionAttribute3 -match "4wp.com") { 
                                        $4wpSMTPAddress = "smtp:" + $emailAlias + "@4wheelparts.com"
                                        Set-ADUser -Server $dc -Identity $adUser.samAccountName -Add @{proxyAddresses="$($4wpSMTPAddress.ToLower())"} -Credential $OnPremCreds
                                    }

                                    ## Set SIP to new email
                                    $SIPAddress = "SIP:" + $newEmail
                                    if (!($adUser.proxyAddresses.Contains($SIPAddress))) {
                                        Log-Write -LineValue "Missing SIP proxyAddress, adding $($SIPAddress).."
                                        Set-ADUser -Server $dc -Identity $adUser.samAccountName -Add @{proxyAddresses=$SIPAddress} -Credential $OnPremCreds
                                    }       
                            }  else {
                                ## Had custom email address but was invalid so process as if it wasn't set  
                            } 
                        }  else {
                            ## No custom email address     
                        }
                        ## End Email Address Configuration

                        ## Assign License Group
                        Log-Write -LineValue "Adding $($adUser.Name) to $($userLicenseGroup) group.."
                        Add-ADGroupMember -Server $dc -Identity $userLicenseGroup -Members $aduser.samAccountName

<#                         ## Remove the license first just in case L1 has added it to the account other wise script errors with "unable to assign license"
                        Log-Write -LineValue "Removing o365 license for $($adUser.Name)"
                        Set-MsolUserLicense -UserPrincipalName $adUser.userPrincipalName -RemoveLicenses $entAccountSkuId -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

                        ## Update as new stuff comes out
                        $disabledOptions = (Get-MsolAccountSku | Where-Object {$_.AccountSkuId -eq $entAccountSkuId} | ForEach-Object {$_.ServiceStatus.serviceplan.servicename} | Where-Object {$_ -notmatch "TEAMS1|SHAREPOINTWAC|SHAREPOINTENTERPRISE|EXCHANGE_S_ENTERPRISE|OFFICESUBSCRIPTION"})
                        $licenseOptions = New-MsolLicenseOptions -AccountSkuId $entAccountSkuId -DisabledPlans $disabledOptions
                        
                        ## Now add the license back with the correct options.
                        Log-Write -LineValue "Adding o365 license for $($adUser.Name)"
                        Set-MsolUserLicense -UserPrincipalName $adUser.userPrincipalName -AddLicenses $entAccountSkuId -LicenseOptions $licenseOptions #>

                        ## Fix GUID (Hybrid deployment only)
                        $exchangeGuid = Get-OnPremRemoteMailbox $adUser.userPrincipalName | ForEach-Object { $_.ExchangeGuid } | Out-Null
                        if ($exchangeGuid -eq "00000000-0000-0000-0000-000000000000" -and $userO365Mailbox.ExchangeGuid -ne "00000000-0000-0000-0000-000000000000") {
                             Log-Write -LineValue "Missing on-prem mailbox GUID for $($adUser.Name), adding.."
                             Set-OnPremRemoteMailbox $adUser.userPrincipalName -ExchangeGuid $userO365Mailbox.ExchangeGuid
                        }

                        ## SIP Check - we need to recheck ad mail attribs after remote mailbox was enabled to get the users email
                        [string]$SAM = $adUser.samAccountName
                        $postadUser = get-aduser -server $dc -filter 'samAccountName -eq $SAM' -Properties mail, proxyAddresses
                        $SIPAddress = "SIP:" + $postadUser.mail
                        if ($SIPAddress -ne "SIP:" -and -not($postadUser.proxyAddresses.Contains($SIPAddress))) {
                            Log-Write -LineValue "$($adUser.Name) missing proxyAddress $SIPAddress, adding.."
                            Set-ADUser -Server $dc -Identity $adUser.samAccountName -Add @{proxyAddresses=$SIPAddress} -Credential $OnPremCreds
                        } else {
                            Log-Write "Couldn't add SIP proxyAddress or already exists for $($adUser.Name): ($($postadUser.mail), $($postadUser.proxyAddresses))"
                        }

                        # Set RecipientType
                        Log-Write -LineValue "Setting msExchRecipientTypeDetails = 1 on $($adUser.Name)"                    
                        Set-ADUser $adUser.samAccountName -Server $dc -Replace @{msExchRemoteRecipientType="1"} -Credential $OnPremCreds   
                        
                        ## Set Mailbox Permissions
                        Log-Write -LineValue "Setting mailbox permissions for $($adUser.Name).."
                        ## Using guid of org mgmt since there is a duplicate somewhere
                        Get-O365Mailbox $adUser.userPrincipalName | Add-O365MailboxPermission -User "5070d319-7ad3-4306-ab68-be2357b7530d" -AccessRights fullaccess -InheritanceType all -AutoMapping $False | Out-Null

	                	## Disable ActiveSync
		                Set-O365CASMailbox -identity $adUser.userPrincipalName -activesyncenabled:$false
	
	                    ## Set values according to Polaris RetainDeletedItemsFor 30 Days policy		
	                    Get-O365Mailbox $adUser.userPrincipalName| Set-O365mailbox -RetainDeletedItemsFor 30.00:00:00

                        ## This command applies the retention policy "Polaris Production Retention Policy" to all new user mailboxes
                        Get-O365Mailbox $adUser.userPrincipalName | Set-O365Mailbox -RetentionPolicy "Polaris Production Retention Policy"

                        ## Write User To User Report
                        Add-Content -Path $reportFile -Value "$($adUser.Name), $($adUser.userPrincipalName), $($adUser.extensionAttribute1.ToLower()), $($adUser.DistinguishedName)"
                                            
                        ## Update users extensionAttribute2 if user completed processing
                        Set-ADUser -Server $dc -Identity $adUser.samAccountName -Replace @{extensionAttribute2="SetupComplete"} -Credential $OnPremCreds

                    } else {
                        ## User doesn't exist in o365 yet, so we cant enable their remote mailbox
                        Log-Write -LineValue "Couldn't find $($adUser.Name) in o365, skipping.."
                    }   
                } else {
                    ## Looks like we're out of enterprise licenses, skip to avoid issues and retry later
                    Log-Write -LineValue "Currently out of o365 licenses, skipping.."
                }
            }
        Log-Write -LineValue "Done."
        }
        ## End User

        ## ExchangeOnly user type (assigns only an exchange license)
        "\bexchangeonly|\bexchangeonlyhidden" { Log-Write -LineValue "Processing $($adUser.Name) as $($adUser.extensionAttribute1.ToLower()).."
        
        ## Validate user requirements
        if ($adUser.extensionAttribute2 -eq "SetupComplete") {
            Log-Write -LineValue "$($adUser.Name) validation failed or already migrated, skipping.."
        } else {
              
            ## Lets make sure we have licenses available
            $licEnterprise = Get-MsolAccountSku | Where-Object { $_.AccountSkuId -like $exchAccountSkuId } | Select-Object *
            $qtyEnterprise = $licEnterprise.ActiveUnits - $licEnterprise.ConsumedUnits
            if ($qtyEnterprise -ge $minLicenseQty) {
                
                ## We have licenses, proceed
                Log-Write -LineValue "Current Exchange licenses available: $qtyEnterprise"
                
                ## Check if user exists in o365 yet (user has to sync to o365 prior to enabling remote mailbox)
                if ($msolUsers -contains $adUser.userPrincipalName) {
                    ## Set usage location
                    Set-MsolUser -UserPrincipalName $adUser.userPrincipalName -UsageLocation US

                    ## If account was partially processed dont try to recreate the mailbox since it will exit loop on failure
                    if (Get-O365Mailbox $adUser.userPrincipalName -ErrorAction SilentlyContinue  | Select-Object * ) {
                        Log-Write -LineValue "Skipping mailbox setup for $($adUser.Name) as mailbox already exists."
                    } else {         
                        ## User is in o365 and we have licenses available so lets enable remote mailbox to configure exch properties (hyrbid only)
                        Log-Write -LineValue "Enabling remote mailbox for $($adUser.Name)"
                        Try {
                            Enable-OnPremRemoteMailbox -Identity $adUser.userPrincipalName -RemoteRoutingAddress "$($adUser.samAccountName)$($routingAddressAppend)@$tenantDomain" -ErrorAction Stop | Out-Null
                        } catch {
                            Log-Write -LineValue "Couldn't enable remote mailbox, aborting: $($Error[0])"
                            Break main
                        }

                        ## After remote mailbox command we need to trigger an ADSync to create the mailbox
                        Log-Write -LineValue "Starting ADSync Delta to begin mailbox creation.."
                        if(!(Get-ADSyncScheduler | Select-Object -expandproperty synccycleinprogress)) {
                            Start-ADSyncSyncCycle -PolicyType Delta -ErrorAction SilentlyContinue | Out-Null
                        } else {
                            Log-Write -LineValue "ADSync already in progress, skipping ADSync trigger.."
                        }

                        ## Lets wait for mailbox creation
                        $abortTimer = 0
                        do {
                            $abortTimer++
                            Log-Write -LineValue "Waiting for O365 to create mailbox for user $($adUser.Name).. [$($abortTimer)] of [$($abortTimerMax)]"
                            $userO365Mailbox = Get-O365Mailbox $adUser.userPrincipalName -ErrorAction SilentlyContinue  | Select-Object * 
                            Start-Sleep 60
                            if ($abortTimer -ge $abortTimerMax) {
                                Log-Write -LineValue "Mailbox wait abort timer hit, aborting.."
                                Break main
                            }
                        }
                        While ($null -eq $userO365Mailbox)
                    }
                    
                    ## Custom Email and SIP Address Configuration - must run after enable-remotemailbox so that mail attributes are populated
                    ## Ignore extensionAttribute3 if a default domain was entered as it would fail trying to add a record that already exists
                    if ($adUser.extensionAttribute3 -and $adUser.extensionAttribute3 -notmatch $defaultMailDomain) {
                        Log-Write -LineValue "extensionAttribute3 is configured, validating.."

                        if ($msolDomains -contains $adUser.extensionAttribute3) {
                                Log-Write -LineValue "$($adUser.extensionAttribute3) is valid msoldomain, configuring new mail address.."
                                
                                ## Custom domain overwrite section
                                if ($adUser.extensionAttribute3 -match "4wheelparts.com") { 
                                    Set-ADUser -Server $dc -Identity $adUser.samAccountName -Replace @{extensionAttribute3="4wp.com"} -Credential $OnPremCreds
                                    $adUser.extensionAttribute3 = "4wp.com"
                                }
                                ## End overwrite section

                                if ($mailFormat -eq "firstlast") {
                                    $emailAlias = $adUser.GivenName + "." + $adUser.Surname
                                } else {
                                    $emailAlias = $adUser.samAccountName
                                }
                                
                                ## Email assignment validation
                                $c = 0
                                do {
                                    if ($c -eq 0) {
                                        $newEmail = $emailAlias + "@" + $adUser.extensionAttribute3
                                        $SMTPAddress = "SMTP:" + $newEmail
                                    } else {
                                        $newEmail = $emailAlias + $c + "@" + $adUser.extensionAttribute3
                                        $SMTPAddress = "SMTP:" + $newEmail
                                    }
                                    $validEmail = Get-ADUser -Server $dc -SearchBase $userSearchBase -Filter {(proxyAddresses -eq $SMTPAddress)}
                                    Log-Write -LineValue "Checking $newEmail availability.."
                                    $c++
                                } while ($validEmail) 
                                Log-Write -LineValue "Configuring new email as $($newEmail).."

                                ## Move current primary to secondary
                                foreach ($proxyaddress in (get-aduser -server $dc -Filter ('userPrincipalName -eq "' + $adUser.userPrincipalName + '"') -Properties proxyAddresses | Select-Object -ExpandProperty proxyAddresses)) {
                                    if ($proxyaddress -cmatch "SMTP:") {
                                        Log-Write -LineValue "Setting $($proxyaddress) to $($proxyaddress.ToLower()).."
                                        Set-ADUser -Server $dc -Identity $adUser.samAccountName -Remove @{proxyAddresses="$($proxyaddress)"} -Credential $OnPremCreds
                                        Set-ADUser -Server $dc -Identity $adUser.samAccountName -Add @{proxyAddresses="$($proxyaddress.ToLower())"} -Credential $OnPremCreds
                                    }
                                }

                                ## Add users new email
                                Log-Write -LineValue "Setting mail attribute to $($newEmail).."
                                Set-ADUser -Server $dc -Identity $adUser.samAccountName -Replace @{mail=$newEmail} -Credential $OnPremCreds
                                Log-Write -LineValue "Adding new primary proxyaddress $($SMTPAddress).."
                                Set-ADUser -Server $dc -Identity $adUser.samAccountName -Add @{proxyAddresses=$SMTPAddress} -Credential $OnPremCreds

                                if ($adUser.extensionAttribute3 -match "4wp.com") { 
                                    $4wpSMTPAddress = "smtp:" + $emailAlias + "@4wheelparts.com"
                                    Set-ADUser -Server $dc -Identity $adUser.samAccountName -Add @{proxyAddresses="$($4wpSMTPAddress.ToLower())"} -Credential $OnPremCreds
                                }

                                ## Set SIP to new email
                                $SIPAddress = "SIP:" + $newEmail
                                if (!($adUser.proxyAddresses.Contains($SIPAddress))) {
                                    Log-Write -LineValue "Missing SIP proxyAddress, adding $($SIPAddress).."
                                    Set-ADUser -Server $dc -Identity $adUser.samAccountName -Add @{proxyAddresses=$SIPAddress} -Credential $OnPremCreds
                                }       
                        }  else {
                            ## Had custom email address but was invalid so process as if it wasn't set  
                        } 
                    }  else {
                        ## No custom email address     
                    }
                    ## End Email Address Configuration

                    ## Assign License Group
                    Log-Write -LineValue "Adding $($adUser.Name) to $($exchangeLicenseGroup) group.."
                    Add-ADGroupMember -Server $dc -Identity $exchangeLicenseGroup -Members $aduser.samAccountName

<#                     ## Remove the license first just in case L1 has added it to the account other wise script errors with "unable to assign license"
                    Log-Write -LineValue "Removing Exchange license for $($adUser.Name)"
                    Set-MsolUserLicense -UserPrincipalName $adUser.userPrincipalName -RemoveLicenses $exchAccountSkuId -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
                   
                    ## Now add the license back with the correct options.
                    Log-Write -LineValue "Adding Exchange license for $($adUser.Name)"
                    Set-MsolUserLicense -UserPrincipalName $adUser.userPrincipalName -AddLicenses $exchAccountSkuId #>

                    ## Fix GUID (Hybrid deployment only)
                    $exchangeGuid = Get-OnPremRemoteMailbox $adUser.userPrincipalName | ForEach-Object { $_.ExchangeGuid } | Out-Null
                    if ($exchangeGuid -eq "00000000-0000-0000-0000-000000000000" -and $userO365Mailbox.ExchangeGuid -ne "00000000-0000-0000-0000-000000000000") {
                         Log-Write -LineValue "Missing on-prem mailbox GUID for $($adUser.Name), adding.."
                         Set-OnPremRemoteMailbox $adUser.userPrincipalName -ExchangeGuid $userO365Mailbox.ExchangeGuid
                    }

                    ## SIP Check - we need to recheck ad mail attribs after remote mailbox was enabled to get the users email
                    [string]$SAM = $adUser.samAccountName
                    $postadUser = get-aduser -server $dc -filter 'samAccountName -eq $SAM' -Properties mail, proxyAddresses
                    $SIPAddress = "SIP:" + $postadUser.mail
                    if ($SIPAddress -ne "SIP:" -and -not($postadUser.proxyAddresses.Contains($SIPAddress))) {
                        Log-Write -LineValue "$($adUser.Name) missing proxyAddress $SIPAddress, adding.."
                        Set-ADUser -Server $dc -Identity $adUser.samAccountName -Add @{proxyAddresses=$SIPAddress} -Credential $OnPremCreds
                    } else {
                        Log-Write "Couldn't add SIP proxyAddress or already exists for $($adUser.Name): ($($postadUser.mail), $($postadUser.proxyAddresses))"
                    }

                    # Set RecipientType
                    Log-Write -LineValue "Setting msExchRecipientTypeDetails = 1 on $($adUser.Name)"                    
                    Set-ADUser $adUser.samAccountName -Server $dc -Replace @{msExchRemoteRecipientType="1"} -Credential $OnPremCreds
                    
                    ## Set Mailbox Permissions
                    Log-Write -LineValue "Setting mailbox permissions for $($adUser.Name).."
                    ## Using guid of org mgmt since there is a duplicate somewhere
                    Get-O365Mailbox $adUser.userPrincipalName | Add-O365MailboxPermission -User "5070d319-7ad3-4306-ab68-be2357b7530d" -AccessRights fullaccess -InheritanceType all -AutoMapping $False | Out-Null

                    ## Disable ActiveSync
                    Set-O365CASMailbox -identity $adUser.userPrincipalName -activesyncenabled:$false

                    ## Set values according to Polaris RetainDeletedItemsFor 30 Days policy		
                    Get-O365Mailbox $adUser.userPrincipalName| Set-O365mailbox -RetainDeletedItemsFor 30.00:00:00

                    ## This command applies the retention policy "Polaris Production Retention Policy" to all new user mailboxes
                    Get-O365Mailbox $adUser.userPrincipalName | Set-O365Mailbox -RetentionPolicy "Polaris Production Retention Policy"

                    if ($adUser.extensionAttribute1.ToLower() -match "exchangeonlyhidden") {
                        Log-Write -LineValue "Setting mailbox as hidden in GAL.."
                        Set-ADUser -Server $dc -Identity $adUser.samAccountName -Replace @{msExchHideFromAddressLists=$True} -Credential $OnPremCreds
                    }

                    ## Write User To User Report
                    Add-Content -Path $reportFile -Value "$($adUser.Name), $($adUser.userPrincipalName), $($adUser.extensionAttribute1.ToLower()), $($adUser.DistinguishedName)"
                                        
                    ## Update users extensionAttribute2 if user completed processing
                    Set-ADUser -Server $dc -Identity $adUser.samAccountName -Replace @{extensionAttribute2="SetupComplete"} -Credential $OnPremCreds
                } else {
                    ## User doesn't exist in o365 yet, so we cant enable their remote mailbox
                    Log-Write -LineValue "Couldn't find $($adUser.Name) in o365, skipping.."
                }   
            } else {
                ## Looks like we're out of enterprise licenses, skip to avoid issues and retry later
                Log-Write -LineValue "Currently out of Exchange licenses, skipping.."
            }
        }
    Log-Write -LineValue "Done."
    }
    ## End ExchangeOnly

    
    ## SMTPrelay (assigns only an exchange license)
    "\bsmtprelay" { Log-Write -LineValue "Processing $($adUser.Name) as $($adUser.extensionAttribute1.ToLower()).."
        
    ## Validate user requirements
    if ($adUser.extensionAttribute2 -eq "SetupComplete") {
        Log-Write -LineValue "$($adUser.Name) validation failed or already migrated, skipping.."
    } else {
          
        ## Lets make sure we have licenses available
        $licEnterprise = Get-MsolAccountSku | Where-Object { $_.AccountSkuId -like $exchAccountSkuId } | Select-Object *
        $qtyEnterprise = $licEnterprise.ActiveUnits - $licEnterprise.ConsumedUnits
        if ($qtyEnterprise -ge $minLicenseQty) {
            
            ## We have licenses, proceed
            Log-Write -LineValue "Current Exchange licenses available: $qtyEnterprise"
            
            ## Check if user exists in o365 yet (user has to sync to o365 prior to enabling remote mailbox)
            if ($msolUsers -contains $adUser.userPrincipalName) {
                ## Set usage location
                Set-MsolUser -UserPrincipalName $adUser.userPrincipalName -UsageLocation US

                ## If account was partially processed dont try to recreate the mailbox since it will exit loop on failure
                if (Get-O365Mailbox $adUser.userPrincipalName -ErrorAction SilentlyContinue  | Select-Object * ) {
                    Log-Write -LineValue "Skipping mailbox setup for $($adUser.Name) as mailbox already exists."
                } else {         
                    ## User is in o365 and we have licenses available so lets enable remote mailbox to configure exch properties (hyrbid only)
                    Log-Write -LineValue "Enabling remote mailbox for $($adUser.Name)"
                    Try {
                        Enable-OnPremRemoteMailbox -Identity $adUser.userPrincipalName -RemoteRoutingAddress "$($adUser.samAccountName)$($routingAddressAppend)@$tenantDomain" -ErrorAction Stop | Out-Null
                    } catch {
                        Log-Write -LineValue "Couldn't enable remote mailbox, aborting: $($Error[0])"
                        Break main
                    }

                    ## After remote mailbox command we need to trigger an ADSync to create the mailbox
                    Log-Write -LineValue "Starting ADSync Delta to begin mailbox creation.."
                    if(!(Get-ADSyncScheduler | Select-Object -expandproperty synccycleinprogress)) {
                        Start-ADSyncSyncCycle -PolicyType Delta -ErrorAction SilentlyContinue | Out-Null
                    } else {
                        Log-Write -LineValue "ADSync already in progress, skipping ADSync trigger.."
                    }

                    ## Lets wait for mailbox creation
                    $abortTimer = 0
                    do {
                        $abortTimer++
                        Log-Write -LineValue "Waiting for O365 to create mailbox for user $($adUser.Name).. [$($abortTimer)] of [$($abortTimerMax)]"
                        $userO365Mailbox = Get-O365Mailbox $adUser.userPrincipalName -ErrorAction SilentlyContinue  | Select-Object * 
                        Start-Sleep 60
                        if ($abortTimer -ge $abortTimerMax) {
                            Log-Write -LineValue "Mailbox wait abort timer hit, aborting.."
                            Break main
                        }
                    }
                    While ($null -eq $userO365Mailbox)
                }
                
                ## Custom Email and SIP Address Configuration - must run after enable-remotemailbox so that mail attributes are populated
                ## Ignore extensionAttribute3 if a default domain was entered as it would fail trying to add a record that already exists
                if ($adUser.extensionAttribute3 -and $adUser.extensionAttribute3 -notmatch $defaultMailDomain) {
                    Log-Write -LineValue "extensionAttribute3 is configured, validating.."

                    if ($msolDomains -contains $adUser.extensionAttribute3) {
                            Log-Write -LineValue "$($adUser.extensionAttribute3) is valid msoldomain, configuring new mail address.."
                            
                            ## Custom domain overwrite section
                            if ($adUser.extensionAttribute3 -match "4wheelparts.com") { 
                                Set-ADUser -Server $dc -Identity $adUser.samAccountName -Replace @{extensionAttribute3="4wp.com"} -Credential $OnPremCreds
                                $adUser.extensionAttribute3 = "4wp.com"
                            }
                            ## End overwrite section

                            if ($mailFormat -eq "firstlast") {
                                $emailAlias = $adUser.GivenName + "." + $adUser.Surname
                            } else {
                                $emailAlias = $adUser.samAccountName
                            }
                            
                            ## Email assignment validation
                            $c = 0
                            do {
                                if ($c -eq 0) {
                                    $newEmail = $emailAlias + "@" + $adUser.extensionAttribute3
                                    $SMTPAddress = "SMTP:" + $newEmail
                                } else {
                                    $newEmail = $emailAlias + $c + "@" + $adUser.extensionAttribute3
                                    $SMTPAddress = "SMTP:" + $newEmail
                                }
                                $validEmail = Get-ADUser -Server $dc -SearchBase $userSearchBase -Filter {(proxyAddresses -eq $SMTPAddress)}
                                Log-Write -LineValue "Checking $newEmail availability.."
                                $c++
                            } while ($validEmail) 
                            Log-Write -LineValue "Configuring new email as $($newEmail).."

                            ## Move current primary to secondary
                            foreach ($proxyaddress in (get-aduser -server $dc -Filter ('userPrincipalName -eq "' + $adUser.userPrincipalName + '"') -Properties proxyAddresses | Select-Object -ExpandProperty proxyAddresses)) {
                                if ($proxyaddress -cmatch "SMTP:") {
                                    Log-Write -LineValue "Setting $($proxyaddress) to $($proxyaddress.ToLower()).."
                                    Set-ADUser -Server $dc -Identity $adUser.samAccountName -Remove @{proxyAddresses="$($proxyaddress)"} -Credential $OnPremCreds
                                    Set-ADUser -Server $dc -Identity $adUser.samAccountName -Add @{proxyAddresses="$($proxyaddress.ToLower())"} -Credential $OnPremCreds
                                }
                            }

                            ## Add users new email
                            Log-Write -LineValue "Setting mail attribute to $($newEmail).."
                            Set-ADUser -Server $dc -Identity $adUser.samAccountName -Replace @{mail=$newEmail} -Credential $OnPremCreds
                            Log-Write -LineValue "Adding new primary proxyaddress $($SMTPAddress).."
                            Set-ADUser -Server $dc -Identity $adUser.samAccountName -Add @{proxyAddresses=$SMTPAddress} -Credential $OnPremCreds

                            if ($adUser.extensionAttribute3 -match "4wp.com") { 
                                $4wpSMTPAddress = "smtp:" + $emailAlias + "@4wheelparts.com"
                                Set-ADUser -Server $dc -Identity $adUser.samAccountName -Add @{proxyAddresses="$($4wpSMTPAddress.ToLower())"} -Credential $OnPremCreds
                            }

                            ## Set SIP to new email
                            $SIPAddress = "SIP:" + $newEmail
                            if (!($adUser.proxyAddresses.Contains($SIPAddress))) {
                                Log-Write -LineValue "Missing SIP proxyAddress, adding $($SIPAddress).."
                                Set-ADUser -Server $dc -Identity $adUser.samAccountName -Add @{proxyAddresses=$SIPAddress} -Credential $OnPremCreds
                            }       
                    }  else {
                        ## Had custom email address but was invalid so process as if it wasn't set  
                    } 
                }  else {
                    ## No custom email address     
                }
                ## End Email Address Configuration

                ## Assign License Group
                Log-Write -LineValue "Adding $($adUser.Name) to $($exchangeLicenseGroup) group.."
                Add-ADGroupMember -Server $dc -Identity $exchangeLicenseGroup -Members $aduser.samAccountName

<#                     ## Remove the license first just in case L1 has added it to the account other wise script errors with "unable to assign license"
                Log-Write -LineValue "Removing Exchange license for $($adUser.Name)"
                Set-MsolUserLicense -UserPrincipalName $adUser.userPrincipalName -RemoveLicenses $exchAccountSkuId -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
               
                ## Now add the license back with the correct options.
                Log-Write -LineValue "Adding Exchange license for $($adUser.Name)"
                Set-MsolUserLicense -UserPrincipalName $adUser.userPrincipalName -AddLicenses $exchAccountSkuId #>

                ## Fix GUID (Hybrid deployment only)
                $exchangeGuid = Get-OnPremRemoteMailbox $adUser.userPrincipalName | ForEach-Object { $_.ExchangeGuid } | Out-Null
                if ($exchangeGuid -eq "00000000-0000-0000-0000-000000000000" -and $userO365Mailbox.ExchangeGuid -ne "00000000-0000-0000-0000-000000000000") {
                     Log-Write -LineValue "Missing on-prem mailbox GUID for $($adUser.Name), adding.."
                     Set-OnPremRemoteMailbox $adUser.userPrincipalName -ExchangeGuid $userO365Mailbox.ExchangeGuid
                }

                ## SIP Check - we need to recheck ad mail attribs after remote mailbox was enabled to get the users email
                [string]$SAM = $adUser.samAccountName
                $postadUser = get-aduser -server $dc -filter 'samAccountName -eq $SAM' -Properties mail, proxyAddresses
                $SIPAddress = "SIP:" + $postadUser.mail
                if ($SIPAddress -ne "SIP:" -and -not($postadUser.proxyAddresses.Contains($SIPAddress))) {
                    Log-Write -LineValue "$($adUser.Name) missing proxyAddress $SIPAddress, adding.."
                    Set-ADUser -Server $dc -Identity $adUser.samAccountName -Add @{proxyAddresses=$SIPAddress} -Credential $OnPremCreds
                } else {
                    Log-Write "Couldn't add SIP proxyAddress or already exists for $($adUser.Name): ($($postadUser.mail), $($postadUser.proxyAddresses))"
                }

                ## Set RecipientType
                Log-Write -LineValue "Setting msExchRecipientTypeDetails = 1 on $($adUser.Name)"                    
                Set-ADUser $adUser.samAccountName -Server $dc -Replace @{msExchRemoteRecipientType="1"} -Credential $OnPremCreds
                
                ## Set Mailbox Permissions
                Log-Write -LineValue "Setting mailbox permissions for $($adUser.Name).."
                ## Using guid of org mgmt since there is a duplicate somewhere
                Get-O365Mailbox $adUser.userPrincipalName | Add-O365MailboxPermission -User "5070d319-7ad3-4306-ab68-be2357b7530d" -AccessRights fullaccess -InheritanceType all -AutoMapping $False | Out-Null

                ## Disable ActiveSync
                Set-O365CASMailbox -identity $adUser.userPrincipalName -activesyncenabled:$false

                ## Set values according to Polaris RetainDeletedItemsFor 7 Days policy		
                Get-O365Mailbox $adUser.userPrincipalName| Set-O365mailbox -RetainDeletedItemsFor 7.00:00:00

                ## This command applies the retention policy "Polaris Production Retention Policy" to all new user mailboxes
                Get-O365Mailbox $adUser.userPrincipalName | Set-O365Mailbox -RetentionPolicy "Polaris Production Retention Policy"

                Log-Write -LineValue "Creating inbox rule.."    
                New-O365InboxRule -mailbox $adUser.userPrincipalName -name "SMTPrelay" -FromAddressContainsWords "@" -DeleteMessage $True -MarkAsRead $True

                Log-Write -LineValue "Setting mailbox auto-reply.."
                Set-O365MailboxAutoReplyConfiguration -Identity $adUser.userPrincipalName -AutoReplyState Enabled -InternalMessage "This is an un-monitored mailbox used for SMTPrelay, for assistance please contact the support department."

                Log-Write -LineValue "Setting mailbox as hidden in GAL.."
                Set-ADUser -Server $dc -Identity $adUser.samAccountName -Replace @{msExchHideFromAddressLists=$True} -Credential $OnPremCreds

                ## Write User To User Report
                Add-Content -Path $reportFile -Value "$($adUser.Name), $($adUser.userPrincipalName), $($adUser.extensionAttribute1.ToLower()), $($adUser.DistinguishedName)"
                                    
                ## Update users extensionAttribute2 if user completed processing
                Set-ADUser -Server $dc -Identity $adUser.samAccountName -Replace @{extensionAttribute2="SetupComplete"} -Credential $OnPremCreds
            } else {
                ## User doesn't exist in o365 yet, so we cant enable their remote mailbox
                Log-Write -LineValue "Couldn't find $($adUser.Name) in o365, skipping.."
            }   
        } else {
            ## Looks like we're out of enterprise licenses, skip to avoid issues and retry later
            Log-Write -LineValue "Currently out of Exchange licenses, skipping.."
        }
    }
Log-Write -LineValue "Done."
}
## End SMTPrelay

        "\broom" {
            Log-Write -LineValue "Processing $($adUser.Name) as $($adUser.extensionAttribute1.ToLower()).."    

            ## Validate room requirements
            if ($adUser.extensionAttribute2 -eq "SetupComplete") {
                Log-Write -LineValue "$($adUser.Name) validation failed or already migrated, skipping.."
            } else {
                ## Check if user exists in o365 yet (user has to sync to o365 prior to enabling remote mailbox)
                if ($msolUsers -contains $adUser.userPrincipalName) {

                    ## If account was partially processed dont try to recreate the mailbox since it will exit loop on failure
                    if (Get-O365Mailbox $adUser.userPrincipalName -ErrorAction SilentlyContinue  | Select-Object * ) {
                        Log-Write -LineValue "Skipping mailbox setup for $($adUser.Name) as mailbox already exists."
                    } else {
                        Log-Write -LineValue "Enabling remote mailbox for $($adUser.Name)"
                        Try {
                            Enable-OnPremRemoteMailbox -Identity $adUser.userPrincipalName -RemoteRoutingAddress "$($adUser.samAccountName)$($routingAddressAppend)@$tenantDomain" -Room | Out-Null
                        } catch {
                            Log-Write -LineValue "Couldn't enable remote mailbox, aborting: $($Error[0])"
                            Break main
                        }

                        ## After remote mailbox command we need to trigger an ADSync to create the mailbox
                        Log-Write -LineValue "Starting ADSync Delta to begin mailbox creation.."
                        if(!(Get-ADSyncScheduler | Select-Object -expandproperty synccycleinprogress)) {
                            Start-ADSyncSyncCycle -PolicyType Delta -ErrorAction SilentlyContinue | Out-Null
                        } else {
                            Log-Write -LineValue "ADSync already in progress, skipping ADSync trigger.."
                        }

                        ## Lets wait for mailbox creation
                        $abortTimer = 0
                        do {
                            $abortTimer++
                            Log-Write -LineValue "Waiting for O365 to create mailbox for user $($adUser.Name).. [$($abortTimer)] of [$($abortTimerMax)]"
                            $userO365Mailbox = Get-O365Mailbox $adUser.userPrincipalName -ErrorAction SilentlyContinue  | Select-Object * 
                            Start-Sleep 60
                            if ($abortTimer -ge $abortTimerMax) {
                                Log-Write -LineValue "Mailbox wait abort timer hit, aborting.."
                                Break main
                            }
                        }
                        While ($null -eq $userO365Mailbox)
                    }                  

                    ## This is to make sure the group exists since it might not in other environments
                    if ($(Get-O365RoleGroup | Where-Object { $_.Name -match $supportGroup })) {
                        Log-Write -LineValue "Adding $($supportGroup) permission on $($adUser.Name)"
		                Get-O365Mailbox $adUser.userPrincipalName| Add-O365MailboxPermission -User $supportGroup -AccessRights fullaccess -InheritanceType all -AutoMapping $False | Out-Null
                    }

                    # Set RecipientType
                    Log-Write -LineValue "Setting msExchRecipientType = 33 on $($adUser.Name)"                    
                    Set-ADUser $adUser.samAccountName -Server $dc -Replace @{msExchRemoteRecipientType="33"} -Credential $OnPremCreds

                    ## Default permission and options
                    write-host "Setting room permissions and options.."     
                    Get-O365Mailbox $adUser.userPrincipalName | Add-O365MailboxPermission -User svcctp03_smtp -AccessRights fullaccess -InheritanceType all -AutoMapping $False | Out-Null            
                    Set-O365MailboxFolderPermission "$($adUser.samAccountName):\Calendar" -User default -AccessRights Author
                    Set-O365CalendarProcessing "$($adUser.userPrincipalName)" -AutomateProcessing $roomAutomateProcessing -BookingWindowInDays $roomBookingWindowInDays -ConflictPercentageAllowed $roomConflictPercentageAllowed -MaximumConflictInstances $roomMaximumConflictInstances -DeleteComments:$roomDeleteComments -RemovePrivateProperty:$roomRemovePrivateProperty -DeleteSubject:$roomDeleteSubject -AddOrganizerToSubject:$roomAddOrganizerToSubject
                    Set-O365CalendarProcessing "$($adUser.samAccountName)" -DeleteComments $False -RemovePrivateProperty $False  -DeleteSubject $False -AddOrganizerToSubject $False

                    # Disable account 
                    Log-Write -LineValue "Disabling mailbox account $($adUser.Name).."
                    Disable-ADAccount -Identity $adUser.samAccountName -Server $dc -Confirm:$false -Credential $OnPremCreds

                    ## Write User To User Report
                    Add-Content -Path $reportFile -Value "$($adUser.Name), $($adUser.userPrincipalName), $($adUser.extensionAttribute1.ToLower()), $($adUser.DistinguishedName)"
                                   
                    ## Update users extensionAttribute2 if user completed processing
                    Set-ADUser -Server $dc -Identity $adUser.samAccountName -Replace @{extensionAttribute2="SetupComplete"} -Credential $OnPremCreds
                } else {
                    ## User doesn't exist in o365 yet, so we cant enable their remote mailbox
                    Log-Write -LineValue "Couldn't find $($adUser.Name) in o365, skipping.."                    
                }
            }
        Log-Write -LineValue "Done."
        }
        ## End room

        "\bequipment" { 
            Log-Write -LineValue "Processing $($adUser.Name) as $($adUser.extensionAttribute1.ToLower()).."    

            ## Validate equipment requirements
            if ($adUser.extensionAttribute2 -eq "SetupComplete") {
                Log-Write -LineValue "$($adUser.Name) validation failed or already migrated, skipping.."
            } else {
                ## Check if user exists in o365 yet (user has to sync to o365 prior to enabling remote mailbox)
                if ($msolUsers -contains $adUser.userPrincipalName) {

                    ## If account was partially processed dont try to recreate the mailbox since it will exit loop on failure
                    if (Get-O365Mailbox $adUser.userPrincipalName -ErrorAction SilentlyContinue  | Select-Object * ) {
                        Log-Write -LineValue "Skipping mailbox setup for $($adUser.Name) as mailbox already exists."
                    } else {                 
                        Log-Write -LineValue "Enabling remote mailbox for $($adUser.Name)"
                        Try {                        
                            Enable-OnPremRemoteMailbox -Identity $adUser.userPrincipalName -RemoteRoutingAddress "$($adUser.samAccountName)$($routingAddressAppend)@$tenantDomain" -Equipment | Out-Null
                        } catch {
                            Log-Write -LineValue "Couldn't enable remote mailbox, aborting: $($Error[0])"
                            Break main
                        }

                        ## After remote mailbox command we need to trigger an ADSync to create the mailbox
                        Log-Write -LineValue "Starting ADSync Delta to begin mailbox creation.."
                        if(!(Get-ADSyncScheduler | Select-Object -expandproperty synccycleinprogress)) {
                            Start-ADSyncSyncCycle -PolicyType Delta -ErrorAction SilentlyContinue | Out-Null
                        } else {
                            Log-Write -LineValue "ADSync already in progress, skipping ADSync trigger.."
                        }

                        ## Lets wait for mailbox creation
                        $abortTimer = 0
                        do {
                            $abortTimer++
                            Log-Write -LineValue "Waiting for O365 to create mailbox for user $($adUser.Name).. [$($abortTimer)] of [$($abortTimerMax)]"
                            $userO365Mailbox = Get-O365Mailbox $adUser.userPrincipalName -ErrorAction SilentlyContinue  | Select-Object * 
                            Start-Sleep 60
                            if ($abortTimer -ge $abortTimerMax) {
                                Log-Write -LineValue "Mailbox wait abort timer hit, aborting.."
                                Break main
                            }
                        }
                        While ($null -eq $userO365Mailbox)
                    } 

                    ## This is to make sure the group exists since it might not in other environments
                    if ($(Get-O365RoleGroup | Where-Object { $_.Name -match $supportGroup })) {
                        Log-Write -LineValue "Adding $($supportGroup) permission on $($adUser.Name)"
		                Get-O365Mailbox $adUser.userPrincipalName| Add-O365MailboxPermission -User $supportGroup -AccessRights fullaccess -InheritanceType all -AutoMapping $False | Out-Null
                    }

                    # Set RecipientType
                    Log-Write -LineValue "Setting msExchRecipientTypeDetails = 65 on $($adUser.Name)"                    
                    Set-ADUser $adUser.samAccountName -Server $dc -Replace @{msExchRemoteRecipientType="65"} -Credential $OnPremCreds

                    # Disable account 
                    Log-Write -LineValue "Disabling mailbox account $($adUser.Name).."
                    Disable-ADAccount -Identity $adUser.samAccountName -Server $dc -Confirm:$false -Credential $OnPremCreds

                    ## Write User To User Report
                    Add-Content -Path $reportFile -Value "$($adUser.Name), $($adUser.userPrincipalName), $($adUser.extensionAttribute1.ToLower()), $($adUser.DistinguishedName)"

                    ## Update users extensionAttribute2 if user completed processing
                    Set-ADUser -Server $dc -Identity $adUser.samAccountName -Replace @{extensionAttribute2="SetupComplete"} -Credential $OnPremCreds
                } else {
                    ## User doesn't exist in o365 yet, so we cant enable their remote mailbox
                    Log-Write -LineValue "Couldn't find $($adUser.Name) in o365, skipping.."                      
                }
            }
        Log-Write -LineValue "Done."
        }
        ## End room

        "\bshared" { 
            Log-Write -LineValue "Processing $($adUser.Name) as $($adUser.extensionAttribute1.ToLower()).."    

            ## Validate requirements
            if ($adUser.extensionAttribute2 -eq "SetupComplete") {
                Log-Write -LineValue "$($adUser.Name) validation failed or already migrated, skipping.."
            } else {
                ## Check if user exists in o365 yet (user has to sync to o365 prior to enabling remote mailbox)
                if ($msolUsers -contains $adUser.userPrincipalName) {

                    ## Set usage location
                    Set-MsolUser -UserPrincipalName $adUser.userPrincipalName -UsageLocation US                  

                    ## If account was partially processed dont try to recreate the mailbox since it will exit loop on failure
                    if (Get-O365Mailbox $adUser.userPrincipalName -ErrorAction SilentlyContinue  | Select-Object * ) {
                        Log-Write -LineValue "Skipping mailbox setup for $($adUser.Name) as mailbox already exists."
                    } else {                  
                        Log-Write -LineValue "Enabling remote mailbox for $($adUser.Name)"
                        Try {
                            Enable-OnPremRemoteMailbox -Identity $adUser.userPrincipalName -RemoteRoutingAddress "$($adUser.samAccountName)$($routingAddressAppend)@$tenantDomain" -Shared | Out-Null
                        } catch {
                            Log-Write -LineValue "Couldn't enable remote mailbox, aborting: $($Error[0])"
                            Break main
                        }

                        ## After remote mailbox command we need to trigger an ADSync to create the mailbox
                        Log-Write -LineValue "Starting ADSync Delta to begin mailbox creation.."
                        if(!(Get-ADSyncScheduler | Select-Object -expandproperty synccycleinprogress)) {
                            Start-ADSyncSyncCycle -PolicyType Delta -ErrorAction SilentlyContinue | Out-Null
                        } else {
                            Log-Write -LineValue "ADSync already in progress, skipping ADSync trigger.."
                        }

                        ##Lets wait for mailbox creation
                        $abortTimer = 0
                        do {
                            $abortTimer++
                            Log-Write -LineValue "Waiting for O365 to create mailbox for user $($adUser.Name).. [$($abortTimer)] of [$($abortTimerMax)]"
                            $userO365Mailbox = Get-O365Mailbox $adUser.userPrincipalName -ErrorAction SilentlyContinue | Select-Object *
                            Start-Sleep 60
                            if ($abortTimer -ge $abortTimerMax) {
                                Log-Write -LineValue "Mailbox wait abort timer hit, aborting.."
                                Break main
                            }
                        }
                        While ($null -eq $userO365Mailbox)
                    }

                    ## Custom Email and SIP Address Configuration - must run after enable-remotemailbox so that mail attributes are populated
                    ## Ignore extensionAttribute3 if a default domain was entered as it would fail trying to add a record that already exists
                    if ($adUser.extensionAttribute3 -and $adUser.extensionAttribute3 -notmatch $defaultMailDomain) {
                        Log-Write -LineValue "extensionAttribute3 is configured, validating.."

                        if ($msolDomains -contains $adUser.extensionAttribute3) {
                                Log-Write -LineValue "$($adUser.extensionAttribute3) is valid msoldomain, configuring new mail address.."
                                
                                ## Custom domain overwrite section
                                if ($adUser.extensionAttribute3 -match "4wheelparts.com") { 
                                    Set-ADUser -Server $dc -Identity $adUser.samAccountName -Replace @{extensionAttribute3="4wp.com"} -Credential $OnPremCreds
                                    $adUser.extensionAttribute3 = "4wp.com"
                                }
                                ## End overwrite section

                                if ($mailFormat -eq "firstlast") {
                                    $emailAlias = $adUser.GivenName + "." + $adUser.Surname
                                } else {
                                    $emailAlias = $adUser.samAccountName
                                }
                                
                                ## Email assignment validation
                                $c = 0
                                do {
                                    if ($c -eq 0) {
                                        $newEmail = $emailAlias + "@" + $adUser.extensionAttribute3
                                        $SMTPAddress = "SMTP:" + $newEmail
                                    } else {
                                        $newEmail = $emailAlias + $c + "@" + $adUser.extensionAttribute3
                                        $SMTPAddress = "SMTP:" + $newEmail
                                    }
                                    $validEmail = Get-ADUser -Server $dc -SearchBase $userSearchBase -Filter {(proxyAddresses -eq $SMTPAddress)}
                                    Log-Write -LineValue "Checking $newEmail availability.."
                                    $c++
                                } while ($validEmail) 
                                Log-Write -LineValue "Configuring new email as $($newEmail).."

                                ## Move current primary to secondary
                                foreach ($proxyaddress in (get-aduser -server $dc -Filter ('userPrincipalName -eq "' + $adUser.userPrincipalName + '"') -Properties proxyAddresses | Select-Object -ExpandProperty proxyAddresses)) {
                                    if ($proxyaddress -cmatch "SMTP:") {
                                        Log-Write -LineValue "Setting $($proxyaddress) to $($proxyaddress.ToLower()).."
                                        Set-ADUser -Server $dc -Identity $adUser.samAccountName -Remove @{proxyAddresses="$($proxyaddress)"} -Credential $OnPremCreds
                                        Set-ADUser -Server $dc -Identity $adUser.samAccountName -Add @{proxyAddresses="$($proxyaddress.ToLower())"} -Credential $OnPremCreds
                                    }
                                }

                                ## Add users new email
                                Log-Write -LineValue "Setting mail attribute to $($newEmail).."
                                Set-ADUser -Server $dc -Identity $adUser.samAccountName -Replace @{mail=$newEmail} -Credential $OnPremCreds
                                Log-Write -LineValue "Adding new primary proxyaddress $($SMTPAddress).."
                                Set-ADUser -Server $dc -Identity $adUser.samAccountName -Add @{proxyAddresses=$SMTPAddress} -Credential $OnPremCreds

                                if ($adUser.extensionAttribute3 -match "4wp.com") { 
                                    $4wpSMTPAddress = "smtp:" + $emailAlias + "@4wheelparts.com"
                                    Set-ADUser -Server $dc -Identity $adUser.samAccountName -Add @{proxyAddresses="$($4wpSMTPAddress.ToLower())"} -Credential $OnPremCreds
                                }

                                ## Set SIP to new email
                                $SIPAddress = "SIP:" + $newEmail
                                if (!($adUser.proxyAddresses.Contains($SIPAddress))) {
                                    Log-Write -LineValue "Missing SIP proxyAddress, adding $($SIPAddress).."
                                    Set-ADUser -Server $dc -Identity $adUser.samAccountName -Add @{proxyAddresses=$SIPAddress} -Credential $OnPremCreds
                                }       
                        }  else {
                            ## Had custom email address but was invalid so process as if it wasn't set  
                        } 
                    }  else {
                        ## No custom email address     
                    }
                    ## End Email Address Configuration

                    # Configure quotas
                    Log-Write -LineValue "Setting quotas on $($adUser.Name)"
                    Get-O365Mailbox $adUser.userPrincipalName | Set-O365Mailbox -ProhibitSendReceiveQuota 50GB -ProhibitSendQuota 49.5GB -IssueWarningQuota 45GB -UseDatabaseQuotaDefaults $false

                    Log-Write -LineValue "Setting $($adUser.Name) mailbox as type shared.."
                    Set-O365Mailbox $adUser.userPrincipalName -Type Shared

                    # Set RecipientTypeDetails
                    Log-Write -LineValue "Setting msExchRecipientTypeDetails = 34359738368 on $($adUser.Name)"                    
                    Set-ADUser $adUser.samAccountName -Server $dc -Replace @{msExchRecipientTypeDetails="34359738368"} -Credential $OnPremCreds

                    # Set RemoteRecipientType
                    Log-Write -LineValue "Setting msExchRemoteRecipientType = 100 on $($adUser.Name)"                    
                    Set-ADUser $adUser.samAccountName -Server $dc -Replace @{msExchRemoteRecipientType="100"} -Credential $OnPremCreds

                    ## SIP Check - we need to recheck ad mail attribs after remote mailbox was enabled to get the users email
                    [string]$SAM = $adUser.samAccountName
                    $postadUser = get-aduser -server $dc -filter 'samAccountName -eq $SAM' -Properties mail, proxyAddresses
                    $SIPAddress = "SIP:" + $postadUser.mail
                    if ($SIPAddress -ne "SIP:" -and -not($postadUser.proxyAddresses.Contains($SIPAddress))) {
                        Log-Write -LineValue "$($adUser.Name) missing proxyAddress $SIPAddress, adding.."
                        Set-ADUser -Server $dc -Identity $adUser.samAccountName -Add @{proxyAddresses=$SIPAddress} -Credential $OnPremCreds
                    } else {
                        Log-Write "Couldn't add SIP proxyAddress or already exists for $($adUser.Name): ($($postadUser.mail), $($postadUser.proxyAddresses))"
                    }
                    
                    ## This is to make sure the group exists since it might not in other environments
                    if ($(Get-O365RoleGroup | Where-Object { $_.Name -match "Polaris_POL_WWSD_ExchangeAdministration" })) {
                        Log-Write -LineValue "Granting Polaris_POL_WWSD_ExchangeAdministration rights on $($adUser.Name)"
    		            Get-O365Mailbox $adUser.userPrincipalName | Add-O365MailboxPermission -User "Polaris_POL_WWSD_ExchangeAdministration" -AccessRights fullaccess -InheritanceType all -AutoMapping $False | Out-Null
                    }

                    ## Fix GUID (Hybrid deployment only)
                    if ((Get-OnPremRemoteMailbox $adUser.userPrincipalName) -eq "00000000-0000-0000-0000-000000000000") {
                        Log-Write -LineValue "Missing on-prem mailbox GUID for $($adUser.Name), adding.."
                        Set-OnPremRemoteMailbox $adUser.userPrincipalName -ExchangeGuid $userO365Mailbox.ExchangeGuid
                    }

                    ## Set Mailbox Permissions
                    Log-Write -LineValue "Setting mailbox permissions for $($adUser.Name).."
                    ## Using guid of org mgmt since there is a duplicate somewhere
                    Get-O365Mailbox $adUser.userPrincipalName | Add-O365MailboxPermission -User "5070d319-7ad3-4306-ab68-be2357b7530d" -AccessRights fullaccess -InheritanceType all -AutoMapping $False | Out-Null

                    ## Disable ActiveSync
                    Set-O365CASMailbox -identity $adUser.userPrincipalName -activesyncenabled:$false

                    ## Set values according to Polaris RetainDeletedItemsFor 30 Days policy		
                    Get-O365Mailbox $adUser.userPrincipalName| Set-O365mailbox -RetainDeletedItemsFor 30.00:00:00

                    ## This command applies the retention policy "Polaris Production Retention Policy" to all new user mailboxes
                    Get-O365Mailbox $adUser.userPrincipalName | Set-O365Mailbox -RetentionPolicy "Polaris Production Retention Policy"
                
                    # Disable account 
                    Log-Write -LineValue "Disabling mailbox account $($adUser.Name).."
                    Disable-ADAccount -Identity $adUser.samAccountName -Server $dc -Confirm:$false -Credential $OnPremCreds

                    ## Write User To User Report
                    Add-Content -Path $reportFile -Value "$($adUser.Name), $($adUser.userPrincipalName), $($adUser.extensionAttribute1.ToLower()), $($adUser.DistinguishedName)"
                    
                    ## Update users extensionAttribute2 if user completed processing
                    Set-ADUser -Server $dc -Identity $adUser.samAccountName -Replace @{extensionAttribute2="SetupComplete"} -Credential $OnPremCreds
                } else {
                    ## User doesn't exist in o365 yet, so we cant enable their remote mailbox
                    Log-Write -LineValue "Couldn't find $($adUser.Name) in o365, skipping.."                     
                }
            }
        Log-Write -LineValue "Done."
        }
        ## End room
    
        default { 
            Log-Write -LineValue "Did not process $($adUser.Name) (extensionAttribute1 is $($adUser.extensionAttribute1.ToLower())), possible incorrect value."
        }
    } 

    ## If user didn't get processed clear extensionAttribute2 (it would be set to setupcomplete if finished)
    if ((get-aduser -Server $dc -Filter ('samAccountName -eq "' + $adUser.samAccountName + '"') -Properties * | select-object -ExpandProperty extensionAttribute2) -eq "Processing") {
        Set-ADUser -Server $dc -Identity $adUser.samAccountName -clear "extensionAttribute2" -Credential $OnPremCreds
    }
}

## Cleanup
Remove-PSSession $OnPrem -Confirm:$false
Remove-PSSession $O365 -Confirm:$false

## Remove old logs
Log-Write -LineValue "Cleaning old logs.."
Get-ChildItem -Path $logPath -Recurse -File -Include *.log | Where-Object CreationTime -lt (Get-Date).AddDays(-$logRetention) | Remove-Item -Force

## Finish
Log-Finish