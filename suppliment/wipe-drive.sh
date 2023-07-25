#!/usr/bin/env bash
# Wipe a drive to prepare for encryption
set -o errexit
set -o nounset
set -o pipefail
if [[ "${TRACE-0}" == "1" ]]; then
    set -o xtrace
fi
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND; exit $s' ERR

# usage
if [[ "${1-}" =~ ^-*h(elp)?$ ]]; then
    echo 'Usage: ./wipe-drive.sh <device>

Uses dm-crypt to wipe the given drive.

'
    exit
fi

if ! [ $(id -u) = 0 ]; then
    echo 'This script must be run as root.'
    exit 1
fi

cryptsetup open --type plain -d /dev/urandom $1 to_be_wiped
dd if=/dev/zero of=/dev/mapper/to_be_wiped bs=1M status=progress
cryptsetup close to_be_wiped
