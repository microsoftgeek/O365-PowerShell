$hts = "mn-host-hybrd-1.cdirad.net"
$dls = @{}
$hts |% {
get-messagetrackinglog -server $_ -EventId expand -start (get-date).toshortdatestring() -resultsize unlimited | % {[int]$dls[$_.relatedrecipientaddress] += 1}
}
$dls

#That will go through your message tracking logs to see what activity (email) has happened on the distribution groups. 
#You would need to run this over time though to determine if mail is coming or going to them, as this will only look at the most recent tracking logs which are usually only a day or two depending on your setup.