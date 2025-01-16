#!/bin/sh

set -e

base="$(dirname "$(readlink -f "$0")")"
cd "$base"

. ../settings.conf

# Prerequisite checks
if ! lsmod | grep -q -e kvm_amd -e kvm_intel; then
    echo "No paravirt support."
    exit 1
fi

if ! lspci -nnk | grep -q "Kernel driver in use: vfio"; then
    echo "No devices are using vfio driver."
    exit 2
fi

# Helpers
get_sys() {
    cat "/proc/sys/$1"
}

set_sys() {
    echo "$2" | sudo tee "/proc/sys/$1"
}

# Hugepages settings
nr_hugepages=$((RAM / 2048))
set_sys vm/nr_hugepages "$nr_hugepages"


# Sound settings
export QEMU_AUDIO_DRV=pa
export QEMU_PA_SAMPLES=8192
export QEMU_AUDIO_TIMER_PERIOD=100
export QEMU_PA_SERVER=/run/user/1000/pulse/native


# UEFI settings
vars="$base/../uefivars.bin"
if ! [ -e "$vars" ]; then
    sudo cp /usr/share/OVMF/OVMF_VARS.fd "$vars"
    sudo chgrp kvm "$vars"
    sudo chmod g+w "$vars"
fi


# Auto-detect number of threads per core. Not in use due to apparent qemu bug
threads="$(lscpu | grep 'Thread(s) per core:' | awk '{print $NF}')"


# Devices to pass
devices='-device ioh3420,bus=pcie.0,addr=1c.0,multifunction=on,port=1,chassis=1,id=root.1'
for i in $(echo "$DEVICES" | sed 's/,/ /g'); do
    id="$(lspci -nnk | grep "$i" | awk '{print $1}')"
    device="-device vfio-pci,host=$id,bus=root.1"
    if [ "$(echo "$id" | cut -d. -f2)" = 0 ]; then
	device="$device,multifunction=on"
    fi
    devices="$devices $device"
done


# Pass extra devices if present
for dev in "Logitech, Inc\. Unifying Receiver" \
	       "Microsoft Corp\. Xbox Wireless Adapter for Windows" \
	       "Nintendo Co\., Ltd Switch Pro Controller"; do
    recv="$(lsusb | grep "$dev$" | awk '{print $6}')"
    if [ -n "$recv" ]; then
	echo "Detected '$dev', passing it to guest."
	vendor="$(echo "$recv" | cut -d: -f1)"
	product="$(echo "$recv" | cut -d: -f2)"
	devices="$devices -device usb-host,vendorid=0x$vendor,productid=0x$product"
    fi
done

# Install media
cdrom=''
if [ -n "$ISO" ]; then
    cdrom="-drive index=0,media=cdrom,file=$ISO"
    # vfio driver ISO from
    # https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso
    cdrom="$cdrom -drive index=1,media=cdrom,file=$base/../virtio-win.iso"
fi


# Network settings
if ! ip link | grep -q "$TAP"; then
    sudo ip tuntap add mode tap "$TAP"
fi

if ! sudo ovs-vsctl show | grep -q "Port $TAP"; then
    sudo ovs-vsctl add-port "$BRIDGE" "$TAP"
    sudo ifconfig "$TAP" up
fi

# Use software rendering if requested
display="-vga none -nographic $devices"
if [ "$1" = 'sw' ]; then
    display=""
fi

glass=''
if ! [ "$1" = 'sw' ] && which looking-glass-client >/dev/null; then
    glass="-device ivshmem-plain,memdev=ivshmem,bus=pcie.0 \
    	   -object memory-backend-file,id=ivshmem,share=on,mem-path=/dev/shm/looking-glass,size=32M \
	   -device virtio-serial-pci \
	   -device virtio-keyboard-pci \
	   -device virtio-mouse-pci \
	   -spice port=5900,addr=127.0.0.1,disable-ticketing=on \
    	   -chardev spicevmc,id=vdagent,name=vdagent \
	   -device virtserialport,chardev=vdagent,name=com.redhat.spice.0"
fi

# RUN!!!1
echo
echo "If looking glass won't connect, capture input and press Win+X, U, R to reboot client."
echo
set -x
qemu-system-x86_64 -name winguest,process=winguest \
		   -machine type=q35,accel=kvm \
		   -cpu host,topoext=on \
		   -smp sockets=1,cores="$CPUS",threads="$threads" \
		   -m "$RAM"M \
		   -rtc clock=host,base=localtime \
		   -serial none -parallel none \
		   -device intel-hda -device hda-duplex \
		   -usb \
		   -device qemu-xhci,id=xhci \
		   $display \
		   -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE.fd \
		   -drive if=pflash,format=raw,file="$vars" \
		   $glass \
		   -drive index=0,id=disk0,if=virtio,cache=none,format=raw,file="$STORAGE" \
		   $cdrom \
		   -nic tap,ifname="$TAP",script=/bin/true,downscript=/bin/true
set +x
echo # make sure the prompt goes on a new line after quitting qemu
