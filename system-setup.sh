#!/bin/bash

set -uo pipefail
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND; exit $s' ERR
# Ensure arch is up-to-date
sudo pacman -Syu

if [[ $(pacman -Qs xf86-video | wc -l) -eq 0 ]]; then
    echo "No Xorg graphics drivers detected"
    echo "Install appropriate graphics driver for: "
    echo "$(lspci | grep -e VGA -e 3d)"
    echo -e "\nAvailable Drivers..."
    echo "$(pacman -Ss xf86-video | grep 'xf86' | sed 's/.*\///' | awk '{print $1}')"
    exit 1
fi

sudo pacman -S --noconfirm \
    pacman-contrib dash xorg-server xorg-xinit xorg-apps youtube-dl \
    libreoffice-fresh pulseaudio pulseaudio-alsa pulsemixer ttf-dejavu stow \
    xdg-user-dirs alacritty imagemagick bc firefox mumble mpv freerdp remmina \
    lshw noto-fonts noto-fonts-cjk noto-fonts-extra ttf-liberation openssh

# XDG Directories
mkdir -vp $HOME/Projects $HOME/Downloads $HOME/Templates $HOME/Shared \
    $HOME/Documents $HOME/Music $HOME/Pictures $HOME/Videos
xdg-user-dirs-update

# Link and Install pacman hook for dash
ln -sfT dash /usr/bin/sh
mkdir -pv /etc/pacman.d/hooks/
cat > /etc/pacman.d/hooks/110-dash-symlink.hook << EOF
[Trigger]
Type = Package
Operation = Install
Operation = Upgrade
Target = bash

[Action]
Description = Re-pointing /bin/sh symlink to dash...
When = PostTransaction
Exec = /usr/bin/ln -sfT dash /usr/bin/sh
Depends = dash
EOF

# Insall yay
DIR=$(pwd)
cd $HOME/.local/src
git clone 'https://aur.archlinux.org/yay.git'
cd yay && makepkg -si
cd $DIR
