Connect-IPPSSession

Get-RetentionCompliancePolicy


# Find the identifier for the retention policy
$Policy = Get-RetentionCompliancePolicy -Identity "Retention Policy for Inactive mailboxes" | Select -ExpandProperty ExchangeObjectId

# Build search string
$CheckGuid = "mbx" + $Policy.Guid.SubString(0,8) + "*"
[array]$Mbx = Get-ExoMailbox -InactiveMailboxOnly -Properties InPlaceHolds

If ($Mbx.Count -eq 0) {Write-Host "No inactive mailboxes found - exiting; break} 
Write-Host ("Processing {0} inactive mailboxes..." -f $Mbx.Count)
ForEach ($M in $Mbx)  {
    $Holds = Get-ExoMailbox -Identity $M.UserPrincipalName -Properties InPlaceHolds -InactiveMailboxOnly | Select -ExpandProperty InPlaceHolds
    If ($Holds -like $CheckGuid) { Write-Host ("The in-place hold for Inactive mailboxes applies to mailbox {0}" -f $User) }
} #End ForEach