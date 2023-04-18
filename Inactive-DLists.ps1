#Set Variables
$EndDate = Get-Date
$StartDate = $EndDate.AddDays(-10)
$Messages = $Null

#Office 365 returns pages of message trace data, so we must keep on asking for pages until no more remain
$Page = 1 
Write-Host "Collecting message trace data for the last 10 days"
Do
{
   $PageOfMessages = (Get-MessageTrace -Status Expanded -PageSize 5000 -Page $Page -StartDate $StartDate -EndDate $EndDate | Select Received, RecipientAddress)
   $Page++
   $Messages += $PageOfMessages
}
Until ($PageOfMessages -eq $Null)


# Build an array of email addresses found in the message trace data
$MessageTable = @{}
$Messagetable = ($Messages | Sort RecipientAddress -Unique | Select RecipientAddress, Received)


# Now get the DLs and check the email address of each against the table
$DLs = Get-DistributionGroup -ResultSize Unlimited
Write-Host "Processing" $DLs.Count "distribution lists..."
$Results = ForEach ($DL in $DLs) {
   If ($MessageTable -Match $DL.PrimarySMTPAddress) {
     [pscustomobject]@{Name = $DL.DisplayName ; Active = "Yes"}
     Write-Host $DL.DisplayName "is active" -Foregroundcolor Yellow }
   Else {
     [pscustomobject]@{Name = $DL.DisplayName ; Active = "No"}
     Write-Host $DL.DisplayName "inactive" -Foregroundcolor Red }
}
$Results | Export-CSV c:\Temp\ListofDLs.csv -NoTypeInformation