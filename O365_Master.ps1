### Office 365 Master Utility
#Requires -RunAsAdministrator

<# README
	Make sure to run the following command in Powershell before using this tool

		Set-ExecutionPolicy RemoteSigned

	This tool requires admin rights to run. Make sure to run as admin before trying to run this tool.
	This tool is to be called from the containing folder using .\O365_Master.ps1 within a Powershell console.
	This tool can be used withing Powershell ISE provided you are running as admin.
#>

# TEST FOR TEAMS
function TST_teamsNotification ([string]$message,[string]$messageTitle,[bool]$goodBad,[string]$color){

	# Change URI to existing Webhook
	$uri = "[Add URI Here]"
	$notification = ""

	# Determine Color on $goodBad
	if($goodBad){
		$notification  = "009F9C (green)"
	} else {
		$notification = "E81123 (red)"
	}

	# Defined color supercedes $goodBad
	if ($null -ne $color){
		$notification = $color
	}

	$body = ConvertTo-JSON @{
		themeColor = $notification
		title = $messageTitle
		text = $message
	}
	Invoke-RestMethod -uri $uri -Method Post -body $body -ContentType 'application/json'
	Write-Output "Message sent to Teams at" + (Get-Date)
}

# Teams Reporting
function teamsNotification ([string]$message,[string]$messageTitle,[bool]$goodBad,[string]$color){

	# Change URI to existing Webhook
	$uri = "[Add URI Here]"
	$notification = ""

	# Determine Color on $goodBad
	if($goodBad){
		$notification  = "009F9C (green)"
	} else {
		$notification = "E81123 (red)"
	}

	# Defined color supercedes $goodBad
	if ($null -ne $color){
		$notification = $color
	}

	$body = ConvertTo-JSON @{
		themeColor = $notification
		title = $messageTitle
		text = $message
	}
	Invoke-RestMethod -uri $uri -Method Post -body $body -ContentType 'application/json'
	Write-Output "Message sent to Teams at" + (Get-Date)
}

# Master Validation Function
function validConfirm([string]$section, [ref]$isValid, [ref]$tempInput) {
	switch ($section) {

		# Email Content Search Validation
		'EMAIL' {
			while ($isValid.Value -ne $true){
				Write-Output "Did you already create a content search in O365 Admin Center?"
				$response = Read-Host -Prompt "Y/N"
				$response = $response.ToUpper()
				switch ($response){
					'Y' { $isValid.Value = $true; break }
					'N' { Write-Output  "Create a Content Search in O365  Admin Center before continuing with this tool"; break }
					default { Write-Output "Invalid entry"; break }
				}
			}
			break
		}

		# Email Purge Validation
		'PURGEVALID' {
			$isValid.Value = $false
			while ($isValid.Value -eq $false){
				switch ($tempInput.Value){
					'H' { $isValid.Value = $true; break }
					'S' { $isValid.Value = $true; break }
					default {
						Write-Output "Invalid Entry"
						$fix = Read-Host -Prompt "[H]ard Purge | [S]oft Purge"
						$fix = $fix.ToUpper()
						$tempInput.Value = $fix
						break
					}
				}
							   
			}
			
		}

		# Main Menu Validation
		'MAINMENU' {
			while  ($isValid.Value -eq $true){
				Clear-Host				

				# Add new  Entry for larger management group
				Write-Output "O365 Master Admin Utility"
				Write-Output "~~~~~~~~~~~~~~~~~~~~~~~~~"
				Write-Output "1 ) Exchange Management"
				Write-Output "0 ) Quit"
				$tempInput.Value = Read-Host  -Prompt "Make a Selection"
				
				switch ($tempInput.Value){
					0 {
						$isValid.Value = $false
						Write-Output "Closing Utility"
						break
					}
					1 {
						# Email Menu
						$menuEmail = $true
						while ($menuEmail){
							menuProcess -menu "EXCHANGE" -continue ([ref]$menuEmail)
						}
						break
					}
					default {
						Write-Output
					}
				}
			}
			
		}

		'DISTY' {
			while($isValid.Value -ne $true){
				Clear-Host
				Write-Host "1 ) List of Distribution Groups"
				Write-Host "2 ) List of Distribution Group Members"
				Write-Host "3 ) List of All Groups and Members"
				Write-Host "0 ) Exit"
				$tempInput.Value = Read-Host -Prompt "Make a Choice"
				if (($tempInput.Value -eq 0) -or ($tempInput.Value -eq 1) -or ($tempInput.Value -eq 2) -or ($tempInput.Value -eq 3)) {
					$isValid.Value = $true
				} else {
					Write-Host "Invalid Entry"
				}
			}
			break
		}

		# Should never be used but here just in case.
		default {
			Write-Output "How the actual hell did you get here?"
			break
		}
	}
}

# Email Purge
function emailPurge (){

	begin{
		try {
			Clear-Host
            CreateSession
		}

		catch{
			$ConnectionError 
			$SessionError
		}
	}

	process {
		try {
			[bool]$validation = $false
			validConfirm -section "EMAIL" -isValid ([ref]$validation)

			If ($validation){
				$ruleName = Read-Host -Prompt "What is the name of the Content Search Rule?"
				$purgeOption = Read-Host -Prompt "[H]ard Purge | [S]oft Purge"
				$purgeOption = $purgeOption.ToUpper()
				validConfirm -section "PURGEVALID" -isValid ([ref]$validation) -tempInput ([ref]$purgeOption)
				#validConfirm('PURGEVALID', [ref]$validation, [ref]$purgeOption)

				switch ($purgeOption){
					'H' {New-ComplianceSearchAction -SearchName $ruleName -Purge -PurgeType HardDelete; break}
					'S' {New-ComplianceSearchAction -SearchName $ruleName -Purge -PurgeType SoftDelete; break}
				}

			} else {
				Write-Output "Something broke. Please close and start again."
			}

			}
		catch {
					
		}
	}

	end {
		try {
			# Cleanup Session
			Remove-PSSession $Session
			Clear-Host
		}
		catch {
			
		}
	}
}

# Main Menu
function mainMenu (){
	$running = $true #checkForUpdate
	$mainOption = ""

	# Exit if Updated
	if (!$running) {  exit }

	while ($running){
		Clear-Host
		validConfirm -section "MAINMENU" -isValid ([ref]$running) -tempInput ([ref]$mainOption)
	}
}

# Menu Processing
function menuProcess ([string]$menu, [ref]$continue){
	Clear-Host
	while ($continue.value -eq $true){
		switch ($menu){
			# Hard add new option from Main Menu
			"EXCHANGE" {
				Clear-Host
				while ($continue.Value -eq $true){
					# Add new option for Exchange tools
					Write-Output "O365 Exchange Menu"
					Write-Output "~~~~~~~~~~~~~~~~~~"
					Write-Output "1 ) Email Purge"
					Write-Output "2 ) Mailbox Quota Report"
					Write-Output "3 ) >30 Days Login Report"
					Write-Output "4 ) List Dist Group Members"
					Write-Output "5 ) Disabled Users w/ Licenses"
					Write-Output "0 ) Quit"
					$temp = Read-Host -Prompt "Make a Selection"

					switch ($temp){
						# Quit
						0  {
							Write-Output "Returning to Main Menu"
							$continue.Value = $false
							break
						}
						# Email Purge
						1   {
							emailPurge
							break;
						}
						#  Mailbox Quota
						2   {
							quotaReport
							break;
						}
						# Last Login
						3   {
							lastLogin
							break;
						}
						# Dist Group members
						4   {
							distMembers
							break
						}
						5   {
							disabledUsers
							break
						}
						default {
							Write-Output "Invalid Selection"
						}
					}
				}
				break
			}
			default { Write-Output "How  the hell did you get here?"; break}
		}
	}
}

function quotaReport { 
	 
	begin { 
		Clear-Host

		try { 
				CreateSession  
			} 
		 
		catch { 
				$ConnectionError 
				$SessionError 
			} 
		} 
		 
	 
	process { 
		 
		try { 
			# Initialize vars
				$Result=@() 
				$mailboxes = Get-Mailbox -ResultSize Unlimited | Sort-Object TotalItemSize
				$totalmbx = $mailboxes.Count

				$i = 0

				# Vars needed for timer
				$count=   @()
				$prevRun   =  Get-Date

				$mailboxes | ForEach-Object {
					$i++
					$mbx = $_
					$mbs = Get-MailboxStatistics $mbx.UserPrincipalName
					
					# Process needed for timer
					$prog = ProgressBar -count ([ref]$count) -prevRun $prevRun

					# Update Progress bar
					Write-Progress -activity "Processing $mbx" -status "$i out of $totalmbx completed" -PercentComplete ($i/$totalmbx*100) -SecondsRemaining (($totalmbx*$prog) - ($i*$prog))
					
					# Needs updated to re-calculate the timer on every run
					$prevRun = Get-Date

					if ($null  -ne $mbs.TotalItemSize){
					$sizeTotal = [math]::Round(($mbs.TotalItemSize.ToString().Split("(")[1].Split(" ")[0].Replace(",","")/1GB),2)
					}else{
						$sizeTotal = 0
					}

					if ($null  -ne $mbx.ProhibitSendReceiveQuota){
						
						$sizeWarning = [math]::Round(($mbx.ProhibitSendReceiveQuota.ToString().Split("(")[1].Split(" ")[0].Replace(",","")/1GB),2)
						$sizeWarning -= ($sizeWarning * .1)
					}else{
						$sizeWarning = 0
					}
					
					
					if (($sizeTotal -gt $sizeWarning<#Change me to adjust capacity test#>) -and ($sizeWarning -gt 0) ){
						$Result += New-Object PSObject -property @{ 
							Name = $mbx.DisplayName
							UserPrincipalName = $mbx.UserPrincipalName
							TotalSizeInGB = $sizeTotal
							QuotaInGB = $mbx.ProhibitSendReceiveQuota                            
							}
					}
				}
				
			# Reset Counter
			$i = 1
			#Processing
			$Result = $Result | Sort-Object TotalSizeInGB -Descending

			Write-Output "$(get-date) : Processing the Results." 
			foreach ( $res in $Result) 
					{ 
						# Format data as table rows
						$body2 += "<tr>" 
						$body2 += "<td>" + $i++ + "</td>"  
						$body2 += "<td>" + $res.Name + "</td>" 
						$body2 += "<td>" + $res.UserPrincipalName + "</td>"
						$body2 += "<td>" + $res.TotalSizeInGB + "</td>"
						$body2 += "<td>" + $res.QuotaInGB + "</td>"
						$body2 += "</tr>" 
					} 
					
			# Format table and headers    
			$body = "<h3>Office 365 {Exchange Online}, User Mailbox Quota Report</h3>" 
			$body += "<br>" 
			$body += "<br>" 
			$body += "<table border=2 style=background-color:silver;border-color:black;color:black >" 
			$body += "<tr>" 
			$body +=  "<th>S. No</th>" 
			$body +=  "<th>Display Name</th>" 
			$body +=  "<th>Email Address</th>" 
			$body += "<th>Total Mailbox  Size</th>"
			$body +=  "<th>Max Inbox Size</th>"
			$body += "</tr>"
			
			# Insert table data
			$body += $body2 
			$body += "</table>" 
				 
		} 
		 
		catch  
			{ 
			 
		} 
	}         
	 
	end { 
			 
		try { 
			 
			#Remvoing the Session with Office 365 
			Write-Output "$(get-date) : Removing PS Session." 
			Remove-PSSession $Script:ouSession

			# Write to Teams
			teamsNotification -message $body -messageTitle "Mailbox Quota Report"  -goodBad $true
			Clear-Host
			} 
			 
		catch { 
			} 
		} 
}

function lastLogin  {
	begin { 
		Clear-Host
	 
		try { 
				CreateSession 
			} 
		 
		catch { 
				$ConnectionError 
				$SessionError 
			 
			} 
		} 
		 
	 
	process { 
		 
		try { 
				# Initialize Vars
				$Result=@() 
				$mailboxes = Get-Mailbox -ResultSize Unlimited
				$totalmbx = $mailboxes.Count

				$i = 0
				$oobDate = (Get-Date).AddDays(-30)
				
				# Vars needed for timer
				$count = @()
				$prevRun = Get-Date

				$mailboxes | ForEach-Object {
					$i++
					$mbx = $_
					$mbs = Get-MailboxStatistics $mbx.UserPrincipalName

					# Used for removal of unwanted accounts in report
					$report = $true

					# Process  needed for timer
					$prog = ProgressBar -count ([ref]$count) -prevRun $prevRun

					# Update Progress bar
					Write-Progress -activity "Processing " -status "$i out of $totalmbx completed" -PercentComplete ($i/$totalmbx*100) -SecondsRemaining (($totalmbx*$prog) - ($i*$prog))
					
					#Needs updates to re-calculate the timer on every run
					$prevRun = Get-Date
					
					# Get Last logon
					$recentLogin = $mbs.LastLogonTime
	
					# Test for never logged in
					if($null -eq $recentLogin){
						$Result += New-Object PSObject -property @{ 
							Name = $mbx.DisplayName
							UserPrincipalName = $mbx.UserPrincipalName
							LastLogon = "Never Logged In"
							}
					}

					$Shared = $mbx.IsShared
	
					# Test all logins
					if(($null -ne $recentLogin) -or ($Shared))  {
						# fallthrough switch to remove accounts unwanted in report
						switch -wildcard ($mbx.DisplayName){
							"Discovery*" {
								$report = $false
								### FALLTHROUGH
							}
							"<*" {
								$report = $false
								### FALLTHROUGH
							}
							">*" {
								$report = $false
								### FALLTHROUGH
							}

						}

						if  ($Shared){
							$report = $false
						}
					}
					
					# Write to array
					if(($recentLogin -lt $oobDate) -and ($report)){
						$Result += New-Object PSObject -property @{ 
							Name = $mbx.DisplayName
							UserPrincipalName = $mbx.UserPrincipalName
							LastLogon = $recentLogin
							}
					}
				}
				
			# Reset Counter
			$i = 1
			#Processing
	
			Write-Output "$(get-date) : Processing the Results." 
			
			if ($Result){
				foreach ( $res in $Result) 
					{ 
						# Format data as table rows
						$body2 += "<tr>" 
						$body2 += "<td>" + $i++ + "</td>"  
						$body2 += "<td>" + $res.Name + "</td>" 
						$body2 += "<td>" + $res.UserPrincipalName + "</td>"
						$body2 += "<td>" + $res.LastLogon + "</td>"
						$body2 += "</tr>" 
					} 
			} else {
				# Format data as table rows
						$body2 += "<tr>" 
						$body2 += "<td>" + $i++ + "</td>"  
						$body2 += "<td>N/A</td>" 
						$body2 += "<td>No Out-dated Maliboxes</td>"
						$body2 += "<td>N/A</td>"
						$body2 += "</tr>"
			}
					
				# Format table and headers    
				$body = "<h3>Office 365, User Mailbox Statics Report.</h3>" 
				$body += "<br>" 
				$body += "<br>" 
				$body += "<table border=2 style=background-color:silver;border-color:black;color:black >" 
				$body += "<tr>" 
				$body +=  "<th>S. No</th>" 
				$body +=  "<th>Display Name</th>" 
				$body +=  "<th>Email Address</th>" 
				$body += "<th>Last Login</th>"
				$body += "</tr>"
				
				# Insert table data
				$body += $body2 
				$body += "</table>" 
				 
			} 
		 
		catch  
			{ 
			 
			} 
		 
		 
	} 
		 
	 
	end { 
			 
		try { 
			 
			#Remvoing the Session with Office 365 
			Write-Output "$(get-date) : Removing PS Session." 
			Remove-PSSession $Script:ouSession
	
			# Write to Teams
			teamsNotification -message $body -messageTitle "Last Login Report" -color "1c3c6c"
			Clear-Host
			} 
			 
		catch { 
			} 
		}
}

function checkForUpdate() {
	$update = $true
	$remotePath = "[Add Path to Master File]"
	$remote = Get-Item $remotePath
	$filePath = Get-Item $PSCommandPath
	If ($filePath.LastWriteTime -lt $remote.LastWriteTime){
		Copy-Item -Path $remotePath -Destination $filePath -Force
		$update = $false
		Write-Output "Script updated. Please re-run script. This script will end."
	}

	Return $update
}

function distMembers(){
	begin {
		Clear-Host
	 
		try { 
				CreateSession  
			} 
		 
		catch { 
				$ConnectionError 
				$SessionError 
			}
	}

	process {
		try{
			$choice = 0
			$Valid = $false
			$DGName = ""
			$DGroups = ""
			$DGMembers = $null
			$Result = @()
			validConfirm -section 'DISTY' -isValid $Valid -tempInput $choice

			# Re-use $Valid to determine if report needs sent
			$Valid = $false

			switch($choice){
				0 {
					break
				}
				# List Groups
				1{
					$DGroups = Get-DistributionGroup -ResultSize Unlimited
					$Valid = $true
					break
				}
				# List Group Members
				2{
					$DGName = Read-Host -Prompt "Distribution Group you want the members of"
					$DGMembers = Get-DistributionGroupMember -Identity $DGName -ResultSize Unlimited | Select Name, PrimarySMTPAddress, RecipientType
					$Valid = $true
					break
				}
				# List all groups and members
				3{
					$DGroups = Get-DistributionGroup -ResultSize Unlimited
					$Valid = $true
					break
				}
				default{
					Write-Host "You were not prepared!"
					break
				}
			}

			if ($choice -ne 0){
				switch($choice){
					1 {
						$DGroups | ForEach-Object {
							$groups = $_
							$Result += New-Object PSObject -property @{
								Member = $member.Name
								EmailAddress = $member.PrimarySMTPAddress
								RecipientType = $member.RecipientType
								}
						}
						break;
					}
					2 {
						$DGMembers | ForEach-Object {
							$member = $_
							$Result += New-Object PSObject -property @{
								Member = $group.Name
								EmailAddress = $group.PrimarySMTPAddress
								}
						}
						break;
					}
					3 {
						$DGroups | ForEach-Object {
						$group = $_
						Get-DistributionGroupMember -Identity $group.Name -ResultSize Unlimited | ForEach-Object {
						$member = $_
						$Result += New-Object PSObject -property @{
							GroupName = $group.DisplayName
							Member = $member.Name
							EmailAddress = $member.PrimarySMTPAddress
							RecipientType = $member.RecipientType
							}
						}}
						break
					}
				}
				
				
			 
			}

		}
		catch{}

	}

	end {
		#Remvoing the Session with Office 365 
			Write-Output "$(get-date) : Removing PS Session." 
			Remove-PSSession $Script:ouSession
	
			# Get file save path
			$saveFile = Get-FileName -initialDirectory "%USERDATA%\Desktop\"

		# Save to CSV
		$Result | Export-CSV $saveFile -NoTypeInformation -Encoding UTF8
	}
}

function Get-FileName($initialDirectory){   
		 [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") |
		 Out-Null

		 $SaveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
		 $SaveFileDialog.initialDirectory = $initialDirectory
		 $SaveFileDialog.filter = “CSV files (*.csv)|*.csv|All files (*.*)|*.*”
		 $SaveFileDialog.ShowDialog() | Out-Null
		 $SaveFileDialog.filename

		return $SaveFileDialog.filename
		}

function CreateSession (){
	Connect-MsolService
    Connect-AzureAD
    Connect-ExchangeOnline
    Connect-IPPSSession
}

function ProgressBar ([ref]$count,[DateTime]$prevRun){
	# Process needed for timer
	$prog = ((Get-Date)-$prevRun)
	$prog = $prog.Seconds
	$count +=  $prog
	$prog = $count | Measure-Object -Average
	$prog = $prog.Average

	# Forces timer to show time if calculation error occurs
	if ($prog -lt 1){$prog = 1}

	return $prog;
}

function disabledUsers (){
	begin { 
		Clear-Host
	    CreateSession
	process { 
		 
		try { 
			# Initialize vars
				$Result=@() 
				$licenses = Get-MsolUser -All | where {$_.isLicensed -eq $true}
				$mailboxes = Get-Mailbox -ResultSize Unlimited | where {$_.SKUAssigned -eq $true}
				$totalmbx = $mailboxes.Count

				$i = 0

				# Vars needed for timer
				$count=   @()
				$prevRun   =  Get-Date


				$mailboxes | ForEach-Object {
					$i++
					$mbx = $_
					$mbs = Get-MailboxStatistics $mbx.UserPrincipalName
					
					$prog = ProgressBar -count ([ref]$count) -prevRun $prevRun

					# Update Progress bar
					Write-Progress -activity "Processing $mbx" -status "$i out of $totalmbx completed" -PercentComplete ($i/$totalmbx*100) -SecondsRemaining (($totalmbx*$prog) - ($i*$prog))
					
					# Needs updated to re-calculate the timer on every run
					$prevRun = Get-Date

									
					
					if ($mbx.AccountDisabled -eq $true){
						$temp = $licenses | where {$mbx.UserPrincipalName -eq $_.UserPrincipalName}
						if ($null -ne $temp){
							foreach ($lic in  $temp.Licenses){
								switch($lic.AccountSku.SkuPartNumber){
									"ENTERPRISEPACK" {
										$license = "E3"
										break
									}
									"STANDARDPACK" {
										$license = "E1"
										break
									}
									"EXCHANGESTANDARD" {
										$license = "Exchange Online"
										break
									}
									default {
										$license = $lic.AccountSku.SkuPartNumber
										break
									}
								}
							}
						}  else {
							$license = "Not Assigned"
						}
						$Result += New-Object PSObject -property @{ 
							Name = $mbx.DisplayName
							UserPrincipalName = $mbx.UserPrincipalName
							License  = $license 
							LastLogon = $mbs.LastLogonTime
							}
					}
				}
				
			# Reset Counter
			$i = 1
			#Processing
			$Result = $Result | Sort-Object Name

			Write-Output "$(get-date) : Processing the Results." 
			foreach ( $res in $Result) 
					{ 
						# Format data as table rows
						$body2 += "<tr>" 
						$body2 += "<td>" + $i++ + "</td>"  
						$body2 += "<td>" + $res.Name + "</td>" 
						$body2 += "<td>" + $res.UserPrincipalName + "</td>"
						$body2 += "<td>" + $res.License + "</td>"
						$body2 += "<td>" + $res.LastLogon + "</td>"
						$body2 += "</tr>" 
					} 
					
			# Format table and headers    
			$body = "<h3>Office 365 {Exchange Online}, Disabled Users and Licences</h3>" 
			$body += "<br>" 
			$body += "<br>" 
			$body += "<table border=2 style=background-color:silver;border-color:black;color:black >" 
			$body += "<tr>" 
			$body +=  "<th>S. No</th>" 
			$body +=  "<th>Display Name</th>" 
			$body +=  "<th>Email Address</th>" 
			$body += "<th>License</th>"
			$body +=  "<th>Last Logon</th>"
			$body += "</tr>"
			
			# Insert table data
			$body += $body2 
			$body += "</table>" 
				 
		} 
		 
		catch  
			{ 
			 
		} 
	}  
}       
	 
	end { 
			 
		try { 
			 
			#Remvoing the Session with Office 365 
			Write-Output "$(get-date) : Removing PS Session." 
			Remove-PSSession $Script:ouSession

			# Write to Teams
			TST_teamsNotification -message $body -messageTitle "Disabled Users w/ Licenses"  -goodBad $true

			} 
			 
		catch { 
			} 
		} 
}

mainMenu
