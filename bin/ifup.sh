#!/bin/sh

set -e

ovs-vsctl add-port br0 "$1"
