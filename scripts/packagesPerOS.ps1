$alma = @(
    "hyperv-daemons"
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