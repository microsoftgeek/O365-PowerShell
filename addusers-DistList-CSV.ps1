#Connect to O365
$UserCredential = Get-Credential
$Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://outlook.office365.com/powershell-liveid/ -Credential $UserCredential -Authentication Basic -AllowRedirection
Import-PSSession $Session

#Add users to DistributionList from CSV
$file=Import-Csv "C:\temp\users.csv"
foreach ($line in $file)
{Add-DistributionGroupMember -identity "DL-CDIUsers" -member $line.alias}