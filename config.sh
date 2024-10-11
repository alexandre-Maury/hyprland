#!/bin/bash

# script config.sh


# Liste des programmes requis pour l'installation
packages=("git" "tar" "curl" "wget")

#Gentoo Base
GENTOO_BASE="https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-systemd-mergedusr/stage3-amd64-systemd-mergedusr-*.tar.xz"
MOUNT_POINT="/mnt"

MODE=""               # <UEFI> ou <BIOS>  
SHRED="On"            # <On> Nettoyage du disque
SHRED_PASS="1"        # Nombre de passe pour le nettoyage


# Comparaison entre Partition Swap et Fichier Swap :
# Critère	    Partition Swap :	                                            Fichier Swap :
# Performance	Généralement plus rapide en raison d'un accès direct.	        Moins rapide, mais souvent suffisant pour la plupart des usages.
# Flexibilité	Taille fixe, nécessite un redimensionnement pour changer.	    Facile à redimensionner en ajoutant ou supprimant des fichiers.
# Simplicité	Nécessite des opérations de partitionnement.	                Plus simple à configurer et à gérer.
# Gestion	    Nécessite des outils de partitionnement pour la création.	    Peut être géré par des commandes simples.

SWAP="On"             # <On> SWAP Activé - <Off> SWAP Désactivé
SWAP_FILE="On"        # <On> Activation du swap avec fichier - Sinon Activation du swap avec partition

MBR_SIZE="256"        # Taille de la partition BOOT/MBR en MiB : /dev/sda1  ext4(8300)   256MiB   /Boot system partition
EFI_SIZE="512"        # Taille de la partition BOOT/EFI en MiB : /dev/sda1  vfat(ef00)   512MiB   /Boot/EFI system partition
ROOT_SIZE="100"       # Taille de la partition pour / en GiB   : /dev/sda2  ext4(8300)   100G     /Racine partition
HOME_SIZE="100"       # Taille de la partition pour /home en % : /dev/sda3  ext4(8300)   100%     /Home partition
SWAP_SIZE="4096"      # Taille du fichier SWAP en MiB


TIMEZONE="Europe/Paris"
LOCALE="fr_FR.UTF-8"
HOSTNAME="gentoo"
INTERFACE="$(ip link show | awk -F': ' '/^[0-9]+: / && !/lo/ {print $2; exit}')"
KEYMAP="fr"
LANGUAGE="fr"

ROOT_PASSWORD="toor"
USERNAME="alexandre"
USERNAME_PASSWORD="azerty"

COMMON_FLAGS="-O2 -pipe -march=native"
CPU_FLAGS=$(grep -m1 "flags" /proc/cpuinfo | cut -d' ' -f2-)
NUM_CORES="-j$(nproc) -l$(nproc)"





