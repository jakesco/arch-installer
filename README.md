# Arch Installer

A [bash script](https://raw.githubusercontent.com/jakesco/arch-installer/refs/heads/master/arch-installer.sh) to install Arch Linux with encrypted drive, zram swap, and systemd-boot.

Boot to a live image and simply follow the prompts in `arch-installer.sh`.

```
# curl -O https://arch.jakesco.com/arch-installer.sh
# bash arch-installer.sh
```

## Wifi on Arch ISO

If you need to connect to wifi for the install process you can use `iwd`.

```
$ iwctl
[iwd]# device list
[iwd]# station <device> connect <SSID>
```

