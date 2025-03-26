param(
    [Parameter(mandatory = $true)]
    [string] $vmName,
    [Parameter(Mandatory = $true)]
    [PSCustomObject] $buildResult,
    [Parameter(Mandatory = $true)]
    [PSCustomObject] $guestIpAddress

)

$smtpServer = "mta.oc.baltsch.com"
$port = 25
$from = "sensiehouse@gmail.com"
$to = "fchorley@gmail.com"

$subject = "$vmName Build " + ($buildResult.success ? "OK" :"Failed" )

if (-not $buildResult.success) { 
    $failTable = "<table border='1'><tr><th>Fail Log</th></tr>"

    #append fails as table rows 
    foreach ($fail in $buildResult.fails) {
        $failTable += "<tr><td>$fail</td></tr>"
    }

    $failTable += "</table>"

}
else { $failTable = "" }

$body = @"
<!DOCTYPE html>
<html>
<body>
    <br/>
    Build returned <strong>$($buildResult.success)</strong>
    <br/>
    <br/>
    <a href="ssh://wigster@$($guestIpAddress)">ssh://wigster@$($guestIpAddress)</a>
</body>

<br/>
    $failTable
</body>
</html>
"@


#console log to stream
$stream = New-Object System.IO.MemoryStream
$writer = New-Object System.IO.StreamWriter $stream
$writer.Write($buildResult.log)
$writer.Flush()
$stream.Position = 0

#create attachment from stream
$attachment = New-Object System.Net.Mail.Attachment $stream, "console_log.txt", "text/plain"

#create mail
$mail = New-Object System.Net.Mail.MailMessage
$mail.From = $from
$mail.To.Add($to)
$mail.Subject = $subject
$mail.Body = $body
$mail.IsBodyHtml = $true 
$mail.Attachments.Add($attachment)

# Set up the SMTP client
$smtp = New-Object System.Net.Mail.SmtpClient $smtpServer, $port
$smtp.Send($mail)

#cleanup
$writer.Dispose()
$stream.Dispose()
$mail.Dispose()
