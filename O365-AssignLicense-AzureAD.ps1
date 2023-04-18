# Connect to Microsoft Online Service
connect-MsolService

# Get all AccountSkuIds
#Get-MsolAccountSku


# Get all users with the Office 365 E3 license
$msolUsers = Get-MsolUser -EnabledFilter EnabledOnly -MaxResults 20000 | Where-Object {($_.licenses).AccountSkuId -eq 'ACProducts:MCOMEETADV'} | Select DisplayName,UserPrincipalName,ObjectId

# Get the Group Id of your new Group. Change searchString to your new group name
$groupId = Get-MsolGroup -SearchString LIC-M365-AUDIOCONF-GROUP | select ObjectId

ForEach ($user in $msolUsers) {
  try {
    # Try to add the user to the new group
    Add-MsolGroupMember -GroupObjectId $groupId.ObjectId -GroupMemberType User -GroupMemberObjectId $user.ObjectId -ErrorAction stop
    [PSCustomObject]@{
      UserPrincipalName = $user.UserPrincipalName
      Migrated          = $true
    }
  }
  catch {
      [PSCustomObject]@{
      UserPrincipalName = $user.UserPrincipalName
      Migrated          = $false
    }
  }
}