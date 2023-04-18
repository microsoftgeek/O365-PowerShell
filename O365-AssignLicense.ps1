# Connect to Microsoft Online Service
connect-MsolService

# Get all AccountSkuIds
#Get-MsolAccountSku


# Assign M365 License
$msolUsers = Get-MsolUser -EnabledFilter EnabledOnly -MaxResults 20000| Where-Object {($_.licenses).AccountSkuId -eq 'ACProducts:MCOMEETADV'} 
ForEach ($user in $msolUsers) {
  try {
    $ADUser = Get-ADUser -filter {UserPrincipalName -eq $user.UserPrincipalName} -ErrorAction stop
    Add-ADGroupMember -Identity LIC-M365-AUDIOCONF-GROUP -Members $ADUser -ErrorAction stop
    [PSCustomObject]@{
      UserPrincipalName = $user.UserPrincipalName
      Migrate           = $true
    }
  }
  catch {
      [PSCustomObject]@{
      UserPrincipalName = $user.UserPrincipalName
      Migrate           = $false
    }
  }
}