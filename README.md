Another set of hyper-v scripts to build Linux and Windows VMs. Server 2025-only right now.

Originally based on https://github.com/schtritoff/hyperv-vm-provisioning - many thanks indeed.

This is for my own personal home network but if anything is useful (apart from the code quality), of course please take. 


## Creating a VM
- NB - Only Server 2025 can be used right now. The code to select which variant is particularly janky still, I'll improve this later

- newVM.ps1 prompts for the OS, VM name/hostname, which Hyper-V virtual switch to use, if a VLAN should be used (one NIC only), and a 'role' (explained below) to be added. For Windows, the admin password is prompted for too, in a horribly insecure way. 

- The process requires admin rights. If newVM.ps1 isn't running as admin, after a prompt for elevation is accepted, the script comtinues in a new window

- All the other scripts were moved to the scripts directory so I don't have to see them. These all require parameters so aren't designed to be called directly


## A Rough Outline of Caching
For use without Node-Red (explained below), entries in build.env can be commented out, and the URLs would be used directly instead. 

I'm really only interested in running the latest cloud images of a few distros, Alma Linux, Debian and Ubuntu, and the Azure variants of Debian and Ubuntu.

Node-Red figures out (nightly and the result is cached) what the latest version of each is.

When newVm.ps1 starts, a prompt appears to choose the OS. When selected, Node-Red is contacted to get the URL and version number.

The image is downloaded and cached in Hyper-V's disk storage location, renamed to include the version, and converted to a VHDX also named to include the version.

If the cache already contains the converted VHDX, this is used so there's no download or conversion. If a newer version of the OS is available, the image is downloaded, converted and renamed, and this newly-converted VHDX is then used. 

For Windows, the same Node-Red logic is used to check for a newer version but, instead of downloading from Microsoft, my NAS is woken and a Windows ISO is downloaded from it. This is then converted to a VHDX and the same caching logic applies. 


## Converting a Windows ISO to a VHDX
I originally built Windows VMs from WDS but, among other things, had to wait for a Windows VM to POST then boot via PXE. This took a while. While searching for alternatives I came across https://github.com/fdcastel/Hyper-V-Automation. It's superb and what you should be looking at. 

Many thanks indeed to fdcastel and the original author! 

That repo uses a script to convert an ISO to a VHDX but I found I couldn't use it in PowerShell Core. For no good reason, I didn't want to be limited so converted that script to something which works in PoSh Core. It should be noted - right now, the Windows ISO is mounted, as is the VHDX file, and are temporarily visible in Explorer. I plan to think about an alternative at some point.


## Cloud-Init 
Although fantastic, I prefer not to create a temporary CD-ROM for Cloud-Init. Instead Cloud-Init's 'seeding' is used by copying files into a Linux guest via WSL. Although commented out (see #wsl -u root chroot /mnt/wsl/$mntID in wslSeedCloudInit.ps1) so the installation is automated, the guest can be entered into during a build, chrooted to the root of the Linux filesystem. 


## Roles
At the moment there are two - Docker and Podman. Whichever is selected gets installed via Ansible. If 'none' is chosen, Ansible is not installed.


## Hyper-V Guest Data Exchange vs Serial Port Output
Although I'd like a VM to be created (after prompts) automatically, I'd also like a rough idea of progress. I used to use Hyper-V's guest data exchange to send a few simple messages back to the PowerShell terminal that's running newVM.ps1. However, this requires the hyper-V integration to be working in the VM. For the latest Alma Linux, Debian Azure, and Ubuntu cloud images at the time of writing, this integration is not available until after a reboot.

Instead, the serial console is monitored and some simple output is shown to provide an overview of progress.


## This is for me
I wasn't planning on making this repo public because of the jankiness. However, I saw someone asking for caching in another repo, and maybe something here would be useful as a start