#!/bin/bash
# Arch install script

# settings to make script fail loudly
set -uo pipefail
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND; exit $s' ERR

if ! [ $(id -u) = 0 ]; then
    echo 'This script must be run as root.'
    exit 1
fi

# for hidpi
echo -n "Use large font? [y/N] "
read large_font
if [[ ${large_font,,} == "y" ]] ; then
    setfont latarcyrheb-sun32
fi

# Check for EFI
if [[ $(ls /sys/firmware/efi/efivars 2> /dev/null | wc -l) -eq 0 ]] ; then
    echo "No EFI detected. This script is for UEFI systems only."
    exit 1
fi

# Check internet connection
if [[ ! $(ping -c1 archlinux.org) ]] ; then
    echo "Unable to connect to intenet."
    echo "Configure internet connection before running this script."
    exit 1
fi

kerneloptions="linux 1\nlinux-hardened 2\nlinux-lts 3\nlinux-zen 4"
kernel=$(dialog --stdout --menu "Select kernel" 0 0 0 $(echo -e "${kerneloptions}")) || exit 1

microcode=$(dialog --stdout --menu "Select microcode package" \
            0 0 0 $(echo -e "intel-ucode 1\namd-ucode 2")) || exit 1
clear

# Get user parameters
echo -n "Enter hostname: "
read hostname
: ${hostname:?'hostname cannot be empty'}

echo -n "Enter admin username: "
read username
: ${username:?'username cannot be empty'}

echo -n "Enter admin password: "
read -s password
: ${password:?'password cannot be empty'}
echo
echo -n "Retype admin password: "
read -s password2
echo
if [[ ! "$password" == "$password2" ]] ; then
    echo "Passwords did not match"
    exit 1
fi

# get disks for install
devicelist=$(lsblk -dpnx size -o name,size | grep -Ev "boot|rpmb|loop" | tac)
device=$(dialog --stdout --menu "Select installation disk" 0 0 0 ${devicelist}) || exit 1
clear

echo "System RAM: $(free --mebi)MiB"
echo -n "Enter swap size in MiB: "
read -s swap_size
: ${swap_size:?'swap size cannot be empty'}
# calculated size of swap partition
swap_end=$(( $swap_size + 261 ))MiB

_message="
Installing arch on $device with...
Hostname: $hostname
Username: $username

Drive $device with be wiped and the following partitions with be created...
BOOT: 260MiB
SWAP: ${swap_size}MiB
ROOT: Rest of drive
"
echo "$_message"

echo -n "Do you wish to continue? [Y/n] "
read confirm
[[ ${confirm,,} == "n" ]] && exit 1

### Install Start ###

# partition drive
parted --script "${device}" mklabel gpt \
    mkpart efi fat32 1Mib 261MiB \
    set 1 boot on \
    mkpart swap linux-swap 261MiB ${swap_end} \
    set 2 swap on \
    mkpart system btrfs ${swap_end} 100%

if [[ $device = *nvme* ]] || [[ $device = *mmcblk* ]]; then
    part_boot="${device}p1"
    part_swap="${device}p2"
    part_root="${device}p3"
else
    part_boot="${device}1"
    part_swap="${device}2"
    part_root="${device}3"
fi

# set time and refresh keys
timedatectl set-ntp true
#echo 'Refreshing keyring...'
#pacman-key --refresh-keys

# start logging
exec &> >(tee "install.log")

# format partitions
wipefs "${part_boot}"
wipefs "${part_root}"
wipefs "${part_swap}"

mkfs.fat -F32 -n EFI /dev/disk/by-partlabel/efi
mkswap -L SWAP /dev/disk/by-partlabel/swap
mkfs.btrfs -L SYSTEM /dev/disk/by-partlabel/system

# Make btrfs subvolumes
mount -t btrfs LABEL=SYSTEM /mnt
btrfs subvolume create /mnt/root
btrfs subvolume create /mnt/home
btrfs subvolume create /mnt/snapshots
umount -R /mnt

# Mount everything
m_opts=compress=lzo,noatime,autodefrag
mount -t btrfs -o defaults,$m_opts,subvol=root LABEL=SYSTEM /mnt
mkdir -p /mnt/boot /mnt/home /mnt/.snapshots
mount -t btrfs -o defaults,$m_opts,subvol=home LABEL=SYSTEM /mnt/home
mount -t btrfs -o defaults,$m_opts,subvol=snapshots LABEL=SYSTEM /mnt/.snapshots
mount LABEL=EFI /mnt/boot
swapon -L SWAP

# Install pacman-contrib and update mirrorlist
pacman -Q pacman-contrib &>/dev/null || sudo pacman -Syq --noconfirm pacman-contrib
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak

curl -s "https://www.archlinux.org/mirrorlist/?country=US&protocol=https&ip_version=4&ip_version=6&uuse_mirror_status=on" | sed -e 's/^#Server/Server/' -e '/^## U/d' | rankmirrors -n 5 - > /etc/pacman.d/mirrorlist

# begin arch install
# Packages
# base linux-zen linux-firmware base-devel
# USERSPACE e2fsprogs, btrfs-progs, exfat-utils, dosfstools
# MAN man-db man-pages texinfo
# OTHER intel/amd-ucode networkmanager ufw neovim git
pacstrap /mnt base ${kernel} linux-firmware base-devel \
              e2fsprogs dosfstools exfat-utils btrfs-progs \
              man-db man-pages texinfo \
              ${microcode} networkmanager ufw neovim git
genfstab -U /mnt >> /mnt/etc/fstab

# set timezone and clock
ln -sf /mnt/usr/share/zoneinfo/America/Los_Angeles /mnt/etc/localtime
arch-chroot /mnt hwclock --systohc

# Set language
sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /mnt/etc/locale.gen
arch-chroot /mnt locale-gen
echo 'LANG=en_US.UTF-8' > /mnt/etc/locale.conf

# Network setup
echo "${hostname}" > /mnt/etc/hostname

cat > /mnt/etc/hosts << EOF
127.0.0.1     localhost
::1           localhost
127.0.1.1     ${hostname}.localdomain ${hostname}
EOF

# Refresh initramfs (only needed with encrypted install)
#arch-chroot /mnt mkinitcpio -P

# Configure systemd-boot
arch-chroot /mnt bootctl --path=/boot install
arch-chroot /mnt bootctl update

mkdir -p /mnt/etc/pacman.d/hooks
cat > /mnt/etc/pacman.d/hooks/100-systemd-boot.hook << EOF
[Trigger]
Type = Package
Operation = Upgrade
Target = systemd

[Action]
Description = Updating systemd-boot.
When = PostTransaction
Exec = /usr/bin/bootctl update
EOF

# Create systemd-boot config files
cat > /mnt/boot/loader/loader.conf << EOF
default arch
timeout 0
console-mode max
editor no
EOF

cat > /mnt/boot/loader/entries/arch.conf << EOF
title Arch Linux
linux /vmlinuz-${kernel}
initrd /${microcode}.img
initrd /initramfs-${kernel}.img
options root=PARTUUID=$(blkid -s PARTUUID -o value "${part_root}") rootflags=subvol=root rw
EOF

# Make pacman pretty
grep "^Color" /mnt/etc/pacman.conf > /dev/null || sed -i "s/^#Color/Color/" /mnt/etc/pacman.conf

# Disable the beep
arch-chroot /mnt rmmod pcspkr
echo "blacklist pcspkr" > /mnt/etc/modprobe.d/nobeep.conf

# Make large font permanent
if [[ ${large_font,,} == "y" ]]; then
cat > /mnt/etc/vconsole.conf << EOF
FONT=latarcyrheb-sun32
FONT_MAP=8859-2
EOF
fi

# Check if device is SSD, if so enable trim timer
if [[ $(lsblk -Ddbpnl -o name,disc-gran | grep "$device" | awk '{print $2}') -gt 0 ]]; then
    arch-chroot /mnt systemctl enable fstrim.timer
fi

# Enable networkmanager and ufw
arch-chroot /mnt systemctl enable NetworkManager.service
arch-chroot /mnt systemctl enable ufw.service
arch-chroot /mnt ufw enable

# add admin user
arch-chroot /mnt useradd -mU -G wheel "$username"

# Change user and root passwords
echo "$username:$password" | arch-chroot /mnt chpasswd
echo "root:$password" | arch-chroot /mnt chpasswd

# Edit sudoers file to enable wheel group
sed -i 's/# %wheel ALL=(ALL) NO/%wheel ALL=(ALL) NO/' /mnt/etc/sudoers

# Disable root password
arch-chroot /mnt passwd -l root

# unmount drive
umount -R /mnt || echo "Failed to unmount /mnt"

# Exit info
echo -e "\nMain install done. reboot and remove iso"
