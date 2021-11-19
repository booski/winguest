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

# Restore information
hugepages_orig=$(get_sys vm/nr_hugepages)

teardown() {
    set +e
    set_sys vm/nr_hugepages "$hugepages_orig"
}

# Ensure restoration
trap teardown EXIT

nr_hugepages=$((RAM / 2048))
set_sys vm/nr_hugepages "$nr_hugepages"

export QEMU_AUDIO_DRV=pa
export QEMU_PA_SAMPLES=8192
export QEMU_AUDIO_TIMER_PERIOD=99
export QEMU_PA_SERVER=/run/user/1000/pulse/native

vars="$(mktemp)"
cp /usr/share/OVMF/OVMF_VARS.fd "$vars"

threads="$(lscpu | grep 'Thread(s) per core:' | awk '{print $NF}')"

devices=''
for i in $(echo "$DEVICES" | sed 's/,/ /g'); do
    id="$(lspci -nnk | grep "$i" | awk '{print $1}')"
    device="-device vfio-pci,host=$id"
    if [ "$(echo "$id" | cut -d. -f2)" = 0 ]; then
	device="$device,multifunction=on"
    fi
    devices="$devices $device"
done

cdrom=''
if [ -n "$ISO" ]; then
    cdrom="-drive index=1,media=cdrom,file=$ISO"
    # vfio driver ISO from
    # https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso
    cdrom="$cdrom -drive index=2,media=cdrom,file=$base/../virtio-win.iso"
fi

set -x
qemu-system-x86_64 -name winguest,process=winguest \
		   -machine type=q35,accel=kvm \
		   -cpu host \
		   -smp "$CPUS",sockets=1,cores="$CPUS",threads="1" \
		   -m "$RAM"M \
		   -rtc clock=host,base=localtime \
		   -vga none -nographic \
		   -serial none -parallel none \
		   -device intel-hda -device hda-duplex \
		   $devices \
		   -drive if=pflash,format=raw,readonly,file=/usr/share/OVMF/OVMF_CODE.fd \
		   -drive if=pflash,format=raw,file="$vars" \
		   -boot order=dc \
		   -drive id=disk0,if=virtio,cache=none,format=raw,file="$STORAGE" \
		   $cdrom
