$textFile = ".\radmail.txt"
$outfile = ".\radmailtrace.txt"
#$email = Get-Content $outfile

Import-module MSOnline
install-module MSOnline

$session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri “https://ps.outlook.com/powershell/” -Credential $cred -Authentication Basic -AllowRedirection -AllowClobber
Import-PSSession $session

$Allmessages = @() 
$P = 1 
do 
{ 
  $pagedmessages = Get-MessageTrace -StartDate (Get-Date -Hour 0 -Minute 00 -Second 00) -EndDate (get-date) -PageSize 1000 -Page $p | Select Received,SenderAddress,RecipientAddress,Size
  $Allmessages += $pagedmessages
  $p = $p + 1 
  
} 
until ($pagedmessages -eq $null) 

$usersset= @("paul.peters@cdirad.com")
foreach($user in $a)
{

$senderssorted = $Allmessages | where{$_.senderaddress -match $user} |group senderaddress | select @{n="SentCount";e={$_.Count}}
$recipientsorted = $Allmessages | where{$_.recipientaddress -match $user} |group recipientaddress | select @{n="ReceivedCount";e={$_.Count}}

$temp = "" | select User,SentCount,ReceivedCount,Total
$temp.User = $user
$temp.Sentcount = $senderssorted.Sentcount
$temp.ReceivedCount = $recipientsorted.ReceivedCount
$temp.Total = $senderssorted.Sentcount + $recipientsorted.ReceivedCount
$temp

}