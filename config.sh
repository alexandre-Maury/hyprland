#!/bin/bash

# script config.sh


# Détection du mode de démarrage (UEFI ou MBR)
if [ -d /sys/firmware/efi ]; then
  MODE="UEFI"
else
  MODE="MBR"
fi

# Comparaison entre Partition Swap et Fichier Swap :
# Critère	    Partition Swap :	                                            Fichier Swap :
# Performance	Généralement plus rapide en raison d'un accès direct.	        Moins rapide, mais souvent suffisant pour la plupart des usages.
# Flexibilité	Taille fixe, nécessite un redimensionnement pour changer.	    Facile à redimensionner en ajoutant ou supprimant des fichiers.
# Simplicité	Nécessite des opérations de partitionnement.	                Plus simple à configurer et à gérer.
# Gestion	    Nécessite des outils de partitionnement pour la création.	    Peut être géré par des commandes simples.

SWAP_FILE="Off" 
SWAP_FILE_SIZE="4096"

# Liste des programmes requis pour l'installation
packages=("git" "tar" "curl" "wget" "chrony")

#Gentoo Base
GENTOO_BASE="https://distfiles.gentoo.org/releases/amd64/autobuilds/20240929T163611Z/stage3-amd64-systemd-20240929T163611Z.tar.xz"
MOUNT_POINT="/mnt/gentoo"


TIMEZONE="Europe/Paris"
LOCALE="fr_FR.UTF-8 UTF-8"
LANG="fr_FR.UTF-8"
HOSTNAME="gentoo-alexandre"
INTERFACE="$(ip link show | awk -F': ' '/^[0-9]+: / && !/lo/ {print $2; exit}')"
KEYMAP="fr"

COMMON_FLAGS="-O2 -pipe -march=native"
CPU_FLAGS=$(grep -m1 "flags" /proc/cpuinfo | cut -d' ' -f2-) # Automatique
MAKEOPTS="-j$(nproc) -l$(nproc)" # Automatique
USE="systemd pam git curl wget tar"
L10N="fr"
INPUT_DEVICES="libinput synaptics keyboard mouse joystick wacom"

USERNAME="alexandre"
PASSWORD_MIN_LEN="4"




