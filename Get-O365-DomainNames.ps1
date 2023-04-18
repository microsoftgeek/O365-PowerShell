#Connect-MsolService cmdlet before calling any other cmdlets
Connect-MsolService



#Use PowerShell to List All Domains in Office 365 Subscription

Get-MsolDomain | Export-CSV o365domains1.csv

#OR

Get-MsolDomain | select Name,capabilities

#OR

Get-MsolDomain | select Name,capabilities | Export-CSV o365domains1.csv