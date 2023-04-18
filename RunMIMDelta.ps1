function RunMa ([string]$MaName, [string]$RunProfile) {
    $curMA = @(get-wmiobject -class "MIIS_ManagementAgent" -namespace "root\MicrosoftIdentityIntegrationServer" -computername "." -filter "Name='$MaName'") 
    if ($curMA.count -eq 0) {throw "MA not found"}
    write-host "`nStarting $RunProfile on $MaName"
    write-host "Result: $($curMA[0].Execute($RunProfile).ReturnValue)"
}
function ClearHistory ([int]$days) {
    $DayDiff = New-Object System.TimeSpan $days, 0, 0, 0, 0
    $DeleteDay = (Get-Date).Subtract($DayDiff)
    Write-Host "`nDeleting run history earlier than or equal to:" $DeleteDay.toString('MM/dd/yyyy')
    $lstSrv = @(get-wmiobject -class "MIIS_SERVER" -namespace "root\MicrosoftIdentityIntegrationServer" -computer ".") 
    Write-Host "Result: " $lstSrv[0].ClearRuns($DeleteDay.toString('yyyy-MM-dd')).ReturnValue
}
 

RunMa -MaName "MIM MA" -RunProfile "DI DS"
RunMa -MaName "ADMA" -RunProfile "DI DS"
RunMa -MaName "ADMA" -RunProfile "E DI"
RunMa -MaName "MIM MA" -RunProfile "E"

Start-sleep -s 30

RunMa -MaName "MIM MA" -RunProfile "DI DS"
RunMa -MaName "ADMA" -RunProfile "E DI"
RunMa -MaName "ADMA" -RunProfile "DS"
RunMa -MaName "MIM MA" -RunProfile "E DI"





#Start-sleep -s 2


ClearHistory -days 1

write-host ""

#$dummy = Read-Host "`nPress ENTER to continue..."