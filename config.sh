#!/bin/bash

# script config.sh

## Détails du montage des partitions :
#     UEFI :

#     BIOS/MBR :


# Liste des programmes requis pour l'installation
packages=("git" "tar" "links" "curl" "wget")

# DISK=$(lsblk -dno NAME,TYPE | awk '$2 == "disk"' | head -n 1)

BLOCK_DEVICE="$(lsblk -nd -o NAME,TYPE | awk '$2 == "disk" {print "/dev/" $1}')"
PART_UEFI="y"
PART_BOOTMBR_SIZE="256"    # Taille de la partition BOOT/MBR en MiB : /dev/sda1  ext4(8300)   256MiB   /Boot system partition
PART_BOOTEFI_SIZE="512"    # Taille de la partition BOOT/EFI en MiB : /dev/sda1  vfat(ef00)   512MiB   /Boot/EFI system partition
PART_ROOT_SIZE="100"       # Taille de la partition pour / en GiB   : /dev/sda2  ext4(8300)   100G     /Racine partition
PART_HOME_SIZE="100"       # Taille de la partition pour /home en % : /dev/sda3  ext4(8300)   100%     /Home partition
FILE_SWAP_SIZE="2048"      # Taille du fichier SWAP en MiB
TIMEZONE="Europe/Paris"
LOCALE="fr_FR.UTF-8 UTF-8"
HOSTNAME="gentoo"
NETWORK_INTERFACE="$(ip link show | awk -F': ' '/^[0-9]+: / && !/lo/ {print $2; exit}')"
KEYMAP="fr"
LANGUAGE="fr"
ROOT_PASSWORD=""
USER=""
USER_PASSWORD=""
COMMON_FLAGS="-O2 -pipe -march=native"
CPU_FLAGS=$(grep -m1 "flags" /proc/cpuinfo | cut -d' ' -f2-)
NUM_CORES=$(nproc)


# # Configuration des utilisateurs supplémentaires
# export ADDITIONAL_USERS="${CFG_ADDITIONAL_USERS:-}"
# # Configuration des groupes
# export ADDITIONAL_GROUPS="${CFG_ADDITIONAL_GROUPS:-users, wheel}"
# # Choix de l'environnement de bureau par défaut
# export DESKTOP_ENV="${CFG_DESKTOP_ENV:-none}"
# # Choix du gestionnaire de fenêtres par défaut
# export WINDOW_MANAGER="${CFG_WINDOW_MANAGER:-i3}"
# # Configuration de la gestion des paquets (portage ou autre)
# export PACKAGE_MANAGER="${CFG_PACKAGE_MANAGER:-portage}"
# # Autres options de configuration
# export ENABLE_SSH="${CFG_ENABLE_SSH:-y}"
# export ENABLE_FIREWALL="${CFG_ENABLE_FIREWALL:-y}"


