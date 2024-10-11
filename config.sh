#!/bin/bash

# script config.sh


# Liste des programmes requis pour l'installation
packages=("git" "tar" "curl" "wget")

#Gentoo Base
GENTOO_BASE="https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-systemd-mergedusr/stage3-amd64-systemd-mergedusr-*.tar.xz"


DISK="SDA"            # Support pour l'installation du systeme  
SWAP="On"             # SWAP <On> OU <Off>
MBR_SIZE="256"        # Taille de la partition BOOT/MBR en MiB : /dev/sda1  ext4(8300)   256MiB   /Boot system partition
EFI_SIZE="512"        # Taille de la partition BOOT/EFI en MiB : /dev/sda1  vfat(ef00)   512MiB   /Boot/EFI system partition
ROOT_SIZE="100"       # Taille de la partition pour / en GiB   : /dev/sda2  ext4(8300)   100G     /Racine partition
HOME_SIZE="100"       # Taille de la partition pour /home en % : /dev/sda3  ext4(8300)   100%     /Home partition
SWAP_SIZE="4096"      # Taille du fichier SWAP en MiB






















# BLOCK_DEVICE="$(lsblk -nd -o NAME,TYPE | awk '$2 == "disk" {print "/dev/" $1}')"


TIMEZONE="Europe/Paris"
LOCALE="fr_FR.UTF-8"
HOSTNAME="gentoo"
INTERFACE="$(ip link show | awk -F': ' '/^[0-9]+: / && !/lo/ {print $2; exit}')"
KEYMAP="fr"
LANGUAGE="fr"
ROOT_PASSWORD=""
USER=""
USER_PASSWORD=""
COMMON_FLAGS="-O2 -pipe -march=native"
CPU_FLAGS=$(grep -m1 "flags" /proc/cpuinfo | cut -d' ' -f2-)
NUM_CORES="-j$(nproc) -l$(nproc)"





