$alma = @(
    "hyperv-daemons",
    "yum-utils"
)

$debian = @(
    "keyboard-configuration"
    ,"console-setup"
    ,"cron"
    ,"hyperv-daemons"
    ,"ansible"
)

$debianAz = @(
   "keyboard-configuration"
   ,"console-setup"
   ,"cron"
   ,"net-tools"
   ,"dnsutils"
   ,"ansible"
)

$ubuntu = @(
   "linux-azure"
   ,"linux-virtual"
   ,"linux-cloud-tools-virtual"
   ,"linux-tools-virtual"
   ,"ansible"
)

$ubuntuAz = @(
    "ansible"
)

return @{
    alma      = $alma
    debian    = $debian
    debianAz  = $debianAz
    ubuntu    = $ubuntu
    ubuntuAz  = $ubuntuAz
}