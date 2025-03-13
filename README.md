Another set of scripts to build hyper-v VMs.

Based on https://github.com/schtritoff/hyperv-vm-provisioning - many thanks indeed - PowerShell scripts to build some Hyper-V VMs.

Cloud-Init and Ansible install a standard set of apps for Linux machines. Node-Red returns the latest version of each distro. 

The dependency on Node-Red can be overidden by setting params in build.env.

Originally based on WDS, now an ISO for Windows machines is downloaded and converted to a VHDX, removing WDS dependency. When searching how to convert an ISO, I came across https://github.com/fdcastel/Hyper-V-Automation. Cheers. This is specifically for my environment, use fdcastel's project instead.
