#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
if [[ "${TRACE-0}" == "1" ]]; then
    set -o xtrace
fi
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND; exit $s' ERR

# usage
if [[ "${1-}" =~ ^-*h(elp)?$ ]]; then
    echo 'Usage: ./desktop-setup.sh

Installs Gnome, nix and enables pipewire, run as user.

'
    exit
fi

# Change to current directory
cd "$(dirname "$0")"

sudo pacman -S gnome ffmpeg ghostty wl-clipboard nix ttf-jetbrains-mono-nerd \
               mesa vulkan-radeon libva-util libva-mesa-driver wireplumber \
               pipewire pipewire-docs pipewire-audio pipwire-pulse pipwire-jack \
               xf86-video-amdgpu ttf-liberation ttf-dejavu noto-fonts noto-fonts-cjk \
               noto-fonts-emoji noto-fonts-extra

# Will need lib32-mesa lib32-vulkan-radeon from multilib if using for steam
sudo usermod -aG nix-users $USER

systemctl --user enable --now pipewire
systemctl --user enable --now pipewire-pulse
sudo systemctl enable gdm.service
sudo systemctl enable nix-daemon.service

mkdir -vp "$HOME/.config/nix"
cat >> $HOME/.config/nix/nix.conf << EOF
experimental-features = nix-command flakes
EOF
