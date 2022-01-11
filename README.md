# winguest
Run a windows VM with GPU acceleration

This set of scripts/configs is intended to get a VM up and running under qemu with 
PCIe passthrough. It is tested on Debian buster.

The VM setup script expects working PulseAudio.

The scripts expect that the GPU to be passed is an AMD GPU with a unique PCI ID, so two identical 
GPUs will cause problems. My testing has been done on AMD Ryzen 7 5700G and AMD Radeon 480, passing 
the 480 to the VM and using the integrated graphics for the host.

## Setup

Clone the repo and copy settings.conf.example to settings.conf and make changes as necessary.

The script `iommu.sh` will output the iommu groups on the system. The scripts expect that the 
devices that are passed are all isolated in one iommu group. If that isn't the case, strange 
things will happen, possibly including the VM not starting at all.

Install the packages listed in `packages.install`, for example:
```bash
sudo apt install $(cat packages.install)
```

The VM startup script expects a bridged network connection, which you will need to manually configure 
before proceeding. The script will configure a virtual network adapter and connect it to
the chosen bridge.
An example `/etc/network/interfaces` file (using openVSwitch):
```
auto br0
allow-ovs br0
iface br0 inet dhcp
      ovs_type OVSBridge
      ovs_ports enp4s0

allow-br0 enp4s0
iface enp4s0 inet manual
      ovs_bridge br0
      ovs_type OVSPort
```

Once settings have been made and required packages are available, run `./update both` from 
inside the repo's base directory, as root, then reboot for changes to take effect. Part of the setup 
involves driver changes, so a reboot is unavoidable (or at least way less trouble than the alternative).

There should now be a winguest.sh script available on your PATH. The script is intended to be run
as a normal user, though it will prompt for a sudo password in order to make some preparations 
before starting the VM.

## Running

`winguest.sh` can be run with the argument `sw` (`winguest.sh sw`) to use software rendering instead of 
the passed GPU. This is useful for debugging/safe mode.

When installing windows, you will probably need to have a display connected to your passed GPU in order 
to be able to install the graphics drivers. Once everything works as expected, I recommend installing
https://looking-glass.io/ for seamless desktop integration without a need for a separate display.

`winguest.sh` will automatically pass the following USB devices if they are detected (as identified by lsusb):
 - Logitech, Inc. Unifying Receiver
 - Microsoft Corp. Xbox One S Controller

I'm too lazy to make them configurable.
