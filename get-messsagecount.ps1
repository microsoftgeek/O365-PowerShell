# Connect to Office365

#$session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri "https://ps.outlook.com/powershell" -Credential $creds -Authentication Basic -AllowRedirection

ForEach ($email in Get-content .\radmail.txt){
    # Get a list of all messages in the last day.
    # $messages = Get-MessageTrace -RecipientAddress paul.peters@cdirad.com -StartDate (Get-Date).AddDays(-1) -EndDate (Get-Date)
    $messages = Get-MessageTrace -RecipientAddress $email -StartDate 10/14/2019 -EndDate 11/14/2019
    Write-Host $email "," $messages.Count
    }
