##-----------------------------------------------------##
##        PICK AUTH Method                             ##
##-----------------------------------------------------##

## HARD CODING PSW    ##
#$password = ConvertTo-SecureString "xxx" -AsPlainText -Force
#$cred = New-Object System.Management.Automation.PSCredential "xxx@xxx.onmicrosofot.com",$password

## USER PROMPT PSW    ##
#$cred = Get-Credential

##-----------------------------------------------------##
##    END PICK
##-----------------------------------------------------##

$url = "https://outlook.office365.com/api/v1.0/me/messages"
$date = "2014-11-21"

## Get all messages that have attachments where received date is greater than $date 
$messageQuery = $url + "?`$select=Id&`$filter=HasAttachments eq true and DateTimeReceived ge " + $date
$messages = Invoke-RestMethod $messageQuery -Credential $cred

## Loop through each results
foreach ($message in $messages.value)
{
    # get attachments and save to file system
    $query = $url + "/" + $message.Id + "/attachments"
    $attachments = Invoke-RestMethod $query -Credential $cred

    # in case of multiple attachments in email
    foreach ($attachment in $attachments.value)
    {
        $attachment.Name
        $path = "c:\Temp\" + $attachment.Name
    
        $Content = [System.Convert]::FromBase64String($attachment.ContentBytes)
        Set-Content -Path $path -Value $Content -Encoding Byte
    }
}

