# Get a handle to the inbox
$inbox = [Microsoft.Exchange.WebServices.Data.Folder]::Bind($s,[Microsoft.Exchange.WebServices.Data.WellKnownFolderName]::Inbox)


# Create a property set (to let us access the building & other details not available from the FindItems call)
$psPropertySet = new-object Microsoft.Exchange.WebServices.Data.PropertySet([Microsoft.Exchange.WebServices.Data.BasePropertySet]::FirstClassProperties)
$psPropertySet.RequestedBodyType = [Microsoft.Exchange.WebServices.Data.BodyType]::Text;


$items = $inbox.FindItems(200)

 

# Get the ID of the folder to move to 
$fvFolderView =  New-Object Microsoft.Exchange.WebServices.Data.FolderView(1000) 
$fvFolderView.Traversal = [Microsoft.Exchange.WebServices.Data.FolderTraversal]::Shallow;
#Put name of folder at the end of the next line
$SfSearchFilter = new-object Microsoft.Exchange.WebServices.Data.SearchFilter+IsEqualTo([Microsoft.Exchange.WebServices.Data.FolderSchema]::DisplayName,"Completed") 
$findFolderResults = $Inbox.FindFolders($SfSearchFilter,$fvFolderView)

# Create counter to add to filename email message to make it unique
$Filter1 = "*.pdf" 
$count = 1

foreach ($item in $items.Items)
{
  # load the property set to allow us to get to the building
  $item.load($psPropertySet)
 
  # Create time stamp to add to filename
  $Date = Get-Date
  $DateM = $Date.Month.toString()
  $DateD = $Date.Day.toString()
  $DateY = $Date.Year.toString()
  $DateH = $Date.Hour.toString()
  $DateMin = $Date.Minute.toString()
  $DateS = $Date.Second.toString()
  $DateMS = $Date.MilliSecond.toString()
  $DateStamp = $DateM + $DateD + $DateY + "_" + $DateH + $DateMin + $DateS + $DateMS
  
 
  # Output the results - first of all the From, Subject, References and Message ID to text file
    $FileName = $item.From.Name + "_" + $DateStamp + "_" + $Count + ".txt"
  
    "From:",$($item.From.Name), "Subject:",$($item.Subject), "Date: ",$($item.DateTimeReceived), $($item.building) | Out-File ($downloadDirectory + "\" + $FileName)
 
 # Create counter to add to filename attachment to make it unique
 
 $countattach = 1
 
  # Loop through the attachments
    foreach($attach in $item.Attachments) {
  
  # Load the attachment
    $attach.Load()
$attach.name -contains ".pdf"
 write-host $attach.name
 
 #countattach = $countattach + 1
 

} 
 
  #$item.Move([Microsoft.Exchange.WebServices.Data.WellKnownFolderName]::DeletedItems)
  #$item.Move($findFolderResults.Folders[0].Id)
 
  $count = $count + 1
 
 
}