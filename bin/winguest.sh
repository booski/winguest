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
    echo "$2" > "/proc/sys/$1"
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

virt-install --name winguest \
	     --virt-type kvm \
	     --os-type=windows --os-variant=win7 \
	     --vcpus="$CPUS" --ram="$RAM" \
	     --cpu host \
	     --disk /dev/hydrogen/windisk \
	     --network type=direct,source="$NIC"
	     --import --transient

