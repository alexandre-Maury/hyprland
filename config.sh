#!/bin/bash

# Configuration des variables

# Liste des programmes à vérifier pour le bon déroulement de l'installation
packages=("git" "tar" "links" "curl" "wget")

DISK=$(lsblk -dno NAME,TYPE | awk '$2 == "disk" {print $1}' | head -n 1)

# Valeurs par défaut
CFG_BLOCK_DEVICE="/dev/${DISK}"
CFG_PART_PREFIX=""
CFG_PART_UEFI="y"
CFG_PART_BOOT_SIZE="256"
CFG_PART_SWAP_SIZE="4096"
CFG_PART_ROOT_SIZE="100%"
CFG_MUSL="n"
CFG_LLVM="n"
CFG_TIMEZONE="Europe/Paris"
CFG_LOCALE="fr_FR.UTF-8 UTF-8"
CFG_HOSTNAME="gentoo"
CFG_NETWORK_INTERFACE="enp0s3"
CFG_KEYMAP="fr"
CFG_USER="alexandre"           # Remplacer par le nom d'utilisateur souhaité
CFG_USER_PASSWORD="azerty"  # Mot de passe pour l'utilisateur