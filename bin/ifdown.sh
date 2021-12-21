#!/bin/sh

set -e

ovs-vsctl del-port br0 "$1"
