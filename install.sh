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

luks_passphrase_prompt () {
    output 'Enter your encryption passphrase (the password will not be shown on the screen):'
    read -r -s luks_passphrase

    if [ -z "${luks_passphrase}" ]; then
        output 'You need to enter a passphrase.'
        luks_passphrase_prompt
    fi

    output 'Confirm your encryption passphrase (the passphrase will not be shown on the screen):'
    read -r -s luks_passphrase2
    if [ "${luks_passphrase}" != "${luks_passphrase2}" ]; then
        output 'Passphrases do not match, please try again.'
        luks_passphrase_prompt
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

luks_passphrase_prompt
disk_prompt
username_prompt
fullname_prompt
user_password_prompt

# Set hardcoded variables (temporary, these will be replaced by future prompts)
locale=en_US
kblayout=us

# Cleaning the TTY
clear

## Updating the live environment usually causes more problems than its worth, and quite often can't be done without remounting cowspace with more capacity
pacman -Sy

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
echo -n "${luks_passphrase}" | cryptsetup luksFormat "${cryptpass}" -d -
echo -n "${luks_passphrase}" | cryptsetup open "${cryptpass}" cryptpass -d -

output 'Creating LUKS Container for the header partition.'
echo -n "${luks_passphrase}" | cryptsetup luksFormat "${crypthead}" -d -
echo -n "${luks_passphrase}" | cryptsetup open "${crypthead}" crypthead -d -

output 'Creating LUKS Container for the root partition.'
echo -n "${luks_passphrase}" | cryptsetup luksFormat "${cryptroot}" --header .header.img -d -
echo -n "${luks_passphrase}" | cryptsetup open "${cryptroot}" cryptroot -d -

## Formatting the partitions
mkfs.xfs -f "${cryptpass}"
mkfs.xfs -f "${crypthead}"
mkfs.xfs -f "${cryptroot}"

## Mount partitions
mount "${cryptroot}" /mnt
mkdir -p /mnt/{boot/efi,passphrase,header}
mount -o nodev,nosuid,noexec "${ESP}" /mnt/boot/efi
mount -o nodev,nosuid,noexec "${cryptpass}" /mnt/passphrase
mount -o nodev,nosuid,noexec "${cryptpass}" /mnt/header

## Save header and passphrase
mv .header.img /mnt/header
chmod 000 /mnt/header/.header.img
echo "${luks_passphrase}" > /mnt/passphrase/.passphrase.txt
chmod 000 /mnt/passphrase/.passphrase.txt

## Pacstrap
output 'Installing the base system (it may take a while).'

output "You may see an error when mkinitcpio tries to generate a new initramfs."
output "It is okay. The script will regenerate the initramfs later in the installation process."

pacstrap /mnt apparmor base chrony efibootmgr firewalld fwupd gdm gnome-console gnome-control-center inotify-tools intel-ucode linux-firmware linux-hardened linux-lts nano nautilus networkmanager pipewire-alsa pipewire-pulse pipewire-jack reflector sbctl sudo zram-generator

# Configure fwupd
echo 'UriSchemes=file;https' | sudo tee -a /mnt/etc/fwupd/fwupd.conf

## Generate /etc/fstab
output 'Generating a new fstab.'
genfstab -U /mnt >> /mnt/etc/fstab

output 'Setting up hostname, locale and keyboard layout' 

## Set hostname
echo 'localhost' > /mnt/etc/hostname

## Setting hosts file
echo 'Setting hosts file.'
echo '# Loopback entries; do not change.
# For historical reasons, localhost precedes localhost.localdomain:
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
# See hosts(5) for proper format and other examples:
# 192.168.1.10 foo.example.org foo
# 192.168.1.13 bar.example.org bar' > /mnt/etc/hosts

## Setup locales
echo "$locale.UTF-8 UTF-8"  > /mnt/etc/locale.gen
echo "LANG=$locale.UTF-8" > /mnt/etc/locale.

## Setup keyboard layout
echo "KEYMAP=$kblayout" > /mnt/etc/vconsole.conf

## Configure /etc/mkinitcpio.conf
output 'Configuring /etc/mkinitcpio for ZSTD compression and LUKS hook.'
sed -i 's/#COMPRESSION="zstd"/COMPRESSION="zstd"/g' /mnt/etc/mkinitcpio.conf
sed -i 's/^MODULES=.*/MODULES=(xfs)/g' /mnt/etc/mkinitcpio.conf
sed -i 's/^HOOKS=.*/HOOKS=(systemd autodetect microcode modconf keyboard sd-vconsole block sd-encrypt)/g' /mnt/etc/mkinitcpio.conf

## Kernel hardening
mkdir -p /etc/cmdline.d/
UUID=$(blkid -s UUID -o value "${cryptroot}")
echo 'root=UUID="${UUID}" ro' > /etc/cmdline.d/root.conf
echo 'lsm=landlock,lockdown,yama,integrity,apparmor,bpf mitigations=auto,nosmt spectre_v2=on spectre_bhi=on spec_store_bypass_disable=on tsx=off kvm.nx_huge_pages=force nosmt=force l1d_flush=on spec_rstack_overflow=safe-ret gather_data_sampling=force reg_file_data_sampling=on random.trust_bootloader=off random.trust_cpu=off intel_iommu=on amd_iommu=force_isolation efi=disable_early_pci_dma iommu=force iommu.passthrough=0 iommu.strict=1 slab_nomerge init_on_alloc=1 init_on_free=1 pti=on vsyscall=none ia32_emulation=0 page_alloc.shuffle=1 randomize_kstack_offset=on debugfs=off lockdown=confidentiality' > /etc/cmdline.d/security.conf

## Continue kernel hardening
unpriv curl -s https://raw.githubusercontent.com/secureblue/secureblue/live/files/system/etc/modprobe.d/blacklist.conf | tee /mnt/etc/modprobe.d/blacklist.conf > /dev/null
if [ "${install_mode}" = 'server' ]; then
    unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/sysctl.d/99-server.conf | tee /mnt/etc/sysctl.d/99-server.conf > /dev/null
else 
    unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/sysctl.d/99-workstation.conf | tee /mnt/etc/sysctl.d/99-workstation.conf > /dev/null
fi

## Setup NTS
unpriv curl -s https://raw.githubusercontent.com/GrapheneOS/infrastructure/main/chrony.conf | tee /mnt/etc/chrony.conf > /dev/null
mkdir -p /mnt/etc/sysconfig
unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/sysconfig/chronyd | tee /mnt/etc/sysconfig/chronyd > /dev/null

## Remove nullok from system-auth
sed -i 's/nullok//g' /mnt/etc/pam.d/system-auth

## Harden SSH
## Arch annoyingly does not split openssh-server out so even desktop Arch will have the daemon

unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/ssh/ssh_config.d/10-custom.conf | tee /mnt/etc/ssh/ssh_config.d/10-custom.conf > /dev/null
unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/ssh/sshd_config.d/10-custom.conf | tee /mnt/etc/ssh/sshd_config.d/10-custom.conf > /dev/null
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /mnt/etc/ssh/sshd_config.d/10-custom.conf
mkdir -p /mnt/etc/systemd/system/sshd.service.d/
unpriv curl -s https://raw.githubusercontent.com/GrapheneOS/infrastructure/main/systemd/system/sshd.service.d/override.conf | tee /mnt/etc/systemd/system/sshd.service.d/override.conf > /dev/null

## Disable coredump
mkdir -p /mnt/etc/security/limits.d/
unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/security/limits.d/30-disable-coredump.conf | tee /mnt/etc/security/limits.d/30-disable-coredump.conf > /dev/null
mkdir -p /mnt/etc/systemd/coredump.conf.d
unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/systemd/coredump.conf.d/disable.conf | tee /mnt/etc/systemd/coredump.conf.d/disable.conf > /dev/null

# Disable XWayland
mkdir -p /mnt/etc/systemd/user/org.gnome.Shell@wayland.service.d
unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/systemd/user/org.gnome.Shell%40wayland.service.d/override.conf | tee /mnt/etc/systemd/user/org.gnome.Shell@wayland.service.d/override.conf > /dev/null


# Setup dconf
# This doesn't actually take effect atm - need to investigate

mkdir -p /mnt/etc/dconf/db/local.d/locks

unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/dconf/db/local.d/locks/automount-disable | tee /mnt/etc/dconf/db/local.d/locks/automount-disable > /dev/null
unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/dconf/db/local.d/locks/privacy | tee /mnt/etc/dconf/db/local.d/locks/privacy > /dev/null

unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/dconf/db/local.d/adw-gtk3-dark | tee /mnt/etc/dconf/db/local.d/adw-gtk3-dark > /dev/null
unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/dconf/db/local.d/automount-disable | tee /mnt/etc/dconf/db/local.d/automount-disable > /dev/null
unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/dconf/db/local.d/button-layout | tee /mnt/etc/dconf/db/local.d/button-layout > /dev/null
unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/dconf/db/local.d/prefer-dark | tee /mnt/etc/dconf/db/local.d/prefer-dark > /dev/null
unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/dconf/db/local.d/privacy | tee /mnt/etc/dconf/db/local.d/privacy > /dev/null
unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/dconf/db/local.d/touchpad | tee /mnt/etc/dconf/db/local.d/touchpad > /dev/null

## ZRAM configuration
unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/systemd/zram-generator.conf | tee /mnt/etc/systemd/zram-generator.conf > /dev/null

## Setup Networking
unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/NetworkManager/conf.d/00-macrandomize.conf | tee /mnt/etc/NetworkManager/conf.d/00-macrandomize.conf > /dev/null
unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/NetworkManager/conf.d/01-transient-hostname.conf | tee /mnt/etc/NetworkManager/conf.d/01-transient-hostname.conf > /dev/null
mkdir -p /mnt/etc/systemd/system/NetworkManager.service.d/
unpriv curl -s https://gitlab.com/divested/brace/-/raw/master/brace/usr/lib/systemd/system/NetworkManager.service.d/99-brace.conf | tee /mnt/etc/systemd/system/NetworkManager.service.d/99-brace.conf > /dev/null

## Configuring the system
arch-chroot /mnt /bin/bash -e <<EOF

    # Setting up timezone
    # Temporarily hardcoding here
    ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime

    # Setting up clock
    hwclock --systohc

    # Generating locales
    locale-gen

    # Create SecureBoot keys
    # This isn't strictly necessary, but linux-hardened preset expects it and mkinitcpio will fail without it
    sbctl create-keys

    # Generating a new initramfs
    chmod 600 /boot/initramfs-linux*
    mkinitcpio -P

    # Adding user with sudo privilege
    useradd -c "$fullname" -m "$username"
    usermod -aG wheel "$username"

    # Setting up dconf
    dconf update
EOF

## Set user password.
[ -n "$username" ] && echo "Setting user password for ${username}." && echo -e "${user_password}\n${user_password}" | arch-chroot /mnt passwd "$username"

## Give wheel user sudo access.
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/g' /mnt/etc/sudoers

## Enable services
systemctl enable apparmor --root=/mnt
systemctl enable chronyd --root=/mnt
systemctl enable firewalld --root=/mnt
systemctl enable fstrim.timer --root=/mnt
systemctl enable gdm --root=/mnt
systemctl enable grub-btrfsd.service --root=/mnt
systemctl enable NetworkManager --root=/mnt
systemctl enable reflector.timer --root=/mnt
systemctl enable snapper-timeline.timer --root=/mnt
systemctl enable snapper-cleanup.timer --root=/mnt
systemctl enable systemd-oomd --root=/mnt
systemctl disable systemd-timesyncd --root=/mnt

rm /mnt/etc/resolv.conf
ln -s /run/systemd/resolve/stub-resolv.conf /mnt/etc/resolv.conf
systemctl enable systemd-resolved --root=/mnt

## Set umask to 077.
sed -i 's/^UMASK.*/UMASK 077/g' /mnt/etc/login.defs
sed -i 's/^HOME_MODE/#HOME_MODE/g' /mnt/etc/login.defs
sed -i 's/umask 022/umask 077/g' /mnt/etc/bash.bashrc

# Finish up
echo "Done, you may now wish to reboot (further changes can be done by chrooting into /mnt)."
exit