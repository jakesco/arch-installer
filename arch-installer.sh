#!/usr/bin/env bash
# Arch install script

PS3="Make a selection: "

# settings to make script fail loudly
set -o errexit
set -o nounset
set -o pipefail
if [[ "${TRACE-0}" == "1" ]]; then
    set -o xtrace
fi
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND; exit $s' ERR

# usage
if [[ "${1-}" =~ ^-*h(elp)?$ ]]; then
    echo 'Usage: ./arch-installer.sh

Runs through the arch installation process. 

'
    exit
fi

# Change to current directory
cd "$(dirname "$0")"

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

# Pick kernel
kerneloptions="linux linux-hardened linux-lts linux-zen"
echo "Which kernel do you want to install?"
select kernel in $kerneloptions; do
    case $kernel in
        linux) break ;;
        linux-hardened) break ;;
        linux-lts) break ;;
        linux-zen) break ;;
        *) echo "Invalid option" ;;
    esac
done
echo "$kernel"

# Pick microcode
echo -e "\nWhich processor manufacturer?"
select microcode in amd intel; do
    case $microcode in
        amd) microcode=amd-ucode
            break
            ;;
        intel) microcode=intel-ucode
            break
            ;;
        *) echo "Invalid option" ;;
    esac
done
echo "$microcode"

# get disks for install
devicelist=$(lsblk -dpnx size -o name,size | grep -Ev "boot|rpmb|loop" | tac)
echo -e "\nAvailable installation devices:\n$devicelist"
devices=$(lsblk -dpnx size -o name | grep -Ev "boot|rpmb|loop" | tr '\n' ' ' | sed -e 's/ $//')
echo -e "\nChoose a device for this Arch installation:"
select device in $devices
do
    break
done
echo "$device"

# Get user and hostname
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

clear

_message="
Installing arch on $device with...
Hostname: $hostname
Username: $username

Kernel: $kernel
Microcode: $microcode

Drive $device will be wiped and the following partitions will be created...
BOOT: 260MiB
ROOT: Rest of drive
SWAP: zram
"
echo "$_message"

echo -n "Do you wish to continue? [Y/n] "
read confirm
[[ ${confirm,,} == "n" ]] && exit 1

### Install Start ###

# start logging
exec &> >(tee "install.log")

# set time
timedatectl set-ntp true

# partition drive
parted --script "${device}" mklabel gpt \
    mkpart efi fat32 1Mib 261MiB \
    set 1 boot on \
    mkpart system btrfs 261MiB 100%

# format partitions
mkfs.fat -F32 -n EFI /dev/disk/by-partlabel/efi
cryptsetup -y -v luksFormat /dev/disk/by-partlabel/system
sleep 1
cryptsetup open /dev/disk/by-partlabel/system root
mkfs.btrfs -f /dev/mapper/root

echo "Creating subvolumes..." && sleep 1
# Make btrfs subvolumes
mount -t btrfs /dev/mapper/root /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@pkg
btrfs subvolume create /mnt/@snapshots
btrfs subvolume set-default /mnt/\@
umount -R /mnt

# Mount everything
echo "Mounting volumes" && sleep 1
m_opts=defaults,noatime,compress=zstd
mount -t btrfs -o $m_opts,subvol=@ /dev/mapper/root /mnt
mount --mkdir -t btrfs -o $m_opts,subvol=@home /dev/mapper/root /mnt/home
mount --mkdir -t btrfs -o $m_opts,subvol=@log /dev/mapper/root /mnt/var/log
mount --mkdir -t btrfs -o $m_opts,subvol=@pkg /dev/mapper/root /mnt/var/cache/pacman/pkg
mount --mkdir -t btrfs -o $m_opts,subvol=@snapshots /dev/mapper/root /mnt/.snapshots
mount --mkdir -t btrfs -o $m_opts,subvolid=5 /dev/mapper/root /mnt/btrfs
mount -t btrfs -o defaults,$m_opts,subvolid=5 LABEL=SYSTEM /mnt/btrfs
mount LABEL=EFI /mnt/boot

# Update mirrorlist
echo "Updating pacman mirrorlist..."
reflector --latest 5 --sort rate --country US --save /etc/pacman.d/mirrorlist

# begin arch install
echo "Bootstraping new install..."
pacstrap -K /mnt base base-devel ${kernel} linux-firmware linux-headers \
              e2fsprogs dosfstools exfat-utils btrfs-progs cryptsetup \
              ${microcode} efibootmgr networkmanager ufw sudo reflector \
              man-db man-pages texinfo neovim git

echo "Configuring new install..."
sleep 1
genfstab -U /mnt >> /mnt/etc/fstab

echo "Enabling zram..."
sleep 1
echo "zram" > /mnt/etc/modules-load.d/zram.conf
echo 'ACTION=="add", KERNEL=="zram0", ATTR{comp_algorithm}="zstd", ATTR{disksize}="4G", RUN="/usr/bin/mkswap -U clear /dev/%k", TAG+="systemd"' > /mnt/etc/udev/rules.d/99.zram.rules
cat >> /mnt/etc/fstab << EOF

# /dev/zram0
/dev/zram0 none swap defaults,pri=100 0 0
EOF

# set timezone and clock
arch-chroot /mnt ln -sf /usr/share/zoneinfo/America/Los_Angeles /etc/localtime
arch-chroot /mnt hwclock --systohc

# Set language
sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /mnt/etc/locale.gen
arch-chroot /mnt locale-gen
echo 'LANG=en_US.UTF-8' > /mnt/etc/locale.conf

# Network setup
echo "${hostname}" > /mnt/etc/hostname

cat >> /mnt/etc/hosts << EOF
127.0.0.1     localhost
::1           localhost
127.0.1.1     ${hostname}.localdomain ${hostname}
EOF

# Edit mkinitcpio.conf hooks
sed -i 's/^\(HOOKS=.*\)file/\1encrypt file/' /mnt/etc/mkinitcpio.conf

# Refresh initramfs
arch-chroot /mnt mkinitcpio -P

# Configure systemd-boot
arch-chroot /mnt bootctl --path=/boot install

mkdir -p /mnt/etc/pacman.d/hooks
cat > /mnt/etc/pacman.d/hooks/100-systemd-boot.hook << EOF
[Trigger]
Type = Package
Operation = Upgrade
Target = systemd

[Action]
Description = Updating systemd-boot.
When = PostTransaction
Exec = /usr/bin/systemctl restart systemd-boot-update.service
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
options cryptdevice=UUID=$(blkid -s UUID -o value /dev/mapper/root):root root=/dev/mapper/root rw quiet splash zswap.enabled=0
EOF

# Make pacman pretty
grep "^Color" /mnt/etc/pacman.conf > /dev/null || sed -i "s/^#Color/Color/" /mnt/etc/pacman.conf

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

# add admin user
arch-chroot /mnt useradd -mU -G wheel "$username"

# Change user and root passwords
echo "$username:$password" | arch-chroot /mnt chpasswd
echo "root:$password" | arch-chroot /mnt chpasswd

# Edit sudoers file to enable wheel group
sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /mnt/etc/sudoers

# Disable root password
arch-chroot /mnt passwd -l root

# unmount drive
umount -R /mnt || echo "Failed to unmount /mnt"

# Exit info
echo -e "\nMain install done. reboot and remove iso"

