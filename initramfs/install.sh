#!/bin/bash

set -e

SCRIPTPATH="$( cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P )"

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

apt-get update
apt-get install -y initramfs-tools
apt-get install -y linux-modules-extra-$(uname -r)
cp -r "$SCRIPTPATH/initramfs-tools" /usr/share
echo brd | sudo tee -a /etc/initramfs-tools/modules
echo zram | sudo tee -a /etc/initramfs-tools/modules
