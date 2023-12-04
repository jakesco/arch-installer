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
    echo 'Usage: ./sway-setup.sh

Installs sway and wm tools on Arch

'
    exit
fi

# Change to current directory
cd "$(dirname "$0")"

sudo pacman -S pipewire pipewire-docs pipewire-audio pipewire-pulse pipewire-jack \
	wireplumber xdg-user-dirs mpv ffmpeg libnotify foot wl-clipboard wlsunset \
	brightnessctl sway swayimg swayidle swaylock swaybg mako \
	ttf-jetbrains-mono-nerd

systemctl --user enable --now pipewire
systemctl --user enable --now pipewire-pulse

xdg-user-dirs-update
