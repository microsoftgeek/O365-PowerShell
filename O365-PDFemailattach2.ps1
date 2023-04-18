$cred = Get-Credential

$sharedMailbox = "shared@contoso.onmicrosoft.com"
$url = "https://outlook.office365.com/api/v1.0/users/$sharedMailbox/messages"
$date = "2016-08-03"

## Get all messages that have attachments where received date is greater than $date 
$messageQuery = $url + "?`$select=Id&`$filter=HasAttachments eq true and DateTimeReceived ge " + $date
$messages = Invoke-RestMethod $messageQuery -Credential $cred

## Loop through each results
foreach ($message in $messages.value){

    # get attachments and save to file system
    $query = $url + "/" + $message.Id + "/attachments"
    $attachments = Invoke-RestMethod $query -Credential $cred

    # in case of multiple attachments in email
    foreach ($attachment in $attachments.value){
        $attachment.Name
        $path = "c:\Temp\" + $attachment.Name
    
        $Content = [System.Convert]::FromBase64String($attachment.ContentBytes)
        Set-Content -Path $path -Value $Content -Encoding Byte
    }

    # Move processed email to a subfolder
    $query = $url + "/" + $message.Id + "/move"
    $body="{""DestinationId"":""AAMkAGRiZmVmOTFlLWJmNjctNDVmZi1iZDkyLTZhOTEzZjI4MGJkNQAuAAAAAAAAkEHub27VS7X8pWwWnKIcAQCxICvUWGkmS6kBXjFB5cP/AADk/q7pAAA=""}"
    Invoke-RestMethod $query -Body $body -ContentType "application/json" -Method post -Credential $cred

}