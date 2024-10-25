#!/bin/bash

# Copyright (C) 2021-2024 Thien Tran, Tommaso Chiti
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy of
# the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations under
# the License.

set -u

output(){
    printf '\e[1;34m%-6s\e[m\n' "${@}"
}

unpriv(){
    sudo -u nobody "$@"
}

luks_password_prompt () {
    output 'Enter your encryption password (the password will not be shown on the screen):'
    read -r -s luks_password

    if [ -z "${luks_password}" ]; then
        output 'You need to enter a password.'
        luks_password_prompt
    fi

    output 'Confirm your encryption password (the password will not be shown on the screen):'
    read -r -s luks_password2
    if [ "${luks_password}" != "${luks_password2}" ]; then
        output 'Passwords do not match, please try again.'
        luks_password_prompt
    fi
}

disk_prompt (){
    lsblk
    output 'Please select the number of the primary disk (e.g. 1):'
    select entry in $(lsblk -dpnoNAME|grep -P "/dev/nvme|sd|mmcblk|vd");
    do
        disk="${entry}"
        output "Arch Linux will be installed on the following disk: ${disk}"
        break
    done
}

username_prompt (){
    output 'Please enter the name for a user account:'
    read -r username

    if [ -z "${username}" ]; then
        output 'Sorry, You need to enter a username.'
        username_prompt
    fi
}

fullname_prompt (){
    output 'Please enter the full name for the user account:'
    read -r fullname

    if [ -z "${fullname}" ]; then
        output 'Please enter the full name of the users account.'
        fullname_prompt
    fi
}

user_password_prompt () {
    output 'Enter your user password (the password will not be shown on the screen):'
    read -r -s user_password

    if [ -z "${user_password}" ]; then
        output 'You need to enter a password.'
        user_password_prompt
    fi

    output 'Confirm your user password (the password will not be shown on the screen):'
    read -r -s user_password2
    if [ "${user_password}" != "${user_password2}" ]; then
        output 'Passwords do not match, please try again.'
        user_password_prompt
    fi
}

luks_password_prompt
disk_prompt
username_prompt
fullname_prompt
user_password_prompt

hostname=localhost
locale=en_US
kblayout=us

## Installing curl
pacman -S --noconfirm curl

## Wipe the disk
sgdisk --zap-all "${disk}"

## Creating a new partition scheme.
output "Creating new partition scheme on ${disk}."
sgdisk -g "${disk}"
sgdisk -I -n 1:0:+1G -t 1:ef00 -c 1:'ESP' "${disk}"
sgdisk -I -n 2:0:+128M -c 2:'passphrase' "${disk}"
sgdisk -I -n 3:0:+128M -c 3:'header' "${disk}"
sgdisk -I -n 4:0:0 -c 4:'rootfs' "${disk}"

ESP='/dev/disk/by-partlabel/ESP'
cryptpass='/dev/disk/by-partlabel/passphrase'
crypthead='/dev/disk/by-partlabel/header'
cryptroot='/dev/disk/by-partlabel/rootfs'

## Informing the Kernel of the changes.
output 'Informing the Kernel about the disk changes.'
partprobe "${disk}"

## Formatting the ESP as FAT32.
output 'Formatting the EFI Partition as FAT32.'
mkfs.fat -F 32 -s 2 "${ESP}"

output 'Creating LUKS Container for the passphrase partition.'
echo -n "${luks_password}" | cryptsetup luksFormat --integrity "${cryptpass}" -d -
echo -n "${luks_password}" | cryptsetup open "${cryptpass}" cryptpass -d -

output 'Creating LUKS Container for the header partition.'
echo -n "${luks_password}" | cryptsetup luksFormat --integrity "${crypthead}" -d -
echo -n "${luks_password}" | cryptsetup open "${crypthead}" crypthead -d -

output 'Creating LUKS Container for the root partition.'
echo -n "${luks_password}" | cryptsetup luksFormat --integrity --header header.img "${cryptroot}" -d -
echo -n "${luks_password}" | cryptsetup open "${cryptroot}" cryptroot -d -

## Formatting the partitions
mkfs.xfs --force ${cryptpass}
mkfs.xfs --force ${crypthead}
mkfs.xfs --force ${cryptroot}