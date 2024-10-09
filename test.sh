#!/bin/bash

# Variables
BLOCK_DEVICE="$(lsblk -nd -o NAME,TYPE | awk '$2 == "disk" {print "/dev/" $1}')"
PART_UEFI="y"
PART_BOOTMBR_SIZE="256"    # Taille de la partition BOOT/MBR en MiB
PART_BOOTEFI_SIZE="512"     # Taille de la partition BOOT/EFI en MiB
PART_ROOT_SIZE="100"        # Taille de la partition pour / en GiB
PART_HOME_SIZE="100"        # Taille de la partition pour /home en %
FILE_SWAP_SIZE="2048"       # Taille du fichier SWAP en MiB

# Vérifier si le disque existe
if [ ! -b "${BLOCK_DEVICE}" ]; then
    echo "Le disque ${BLOCK_DEVICE} n'existe pas."
    exit 1
fi

# Choisir le type de nettoyage
echo "Choisissez le type de nettoyage du disque ${BLOCK_DEVICE} :"
echo "1. Nettoyage avec des zéros"
echo "2. Nettoyage avec des données aléatoires"
read -rp "Entrez votre choix (1 ou 2) : " CLEAN_OPTION

# Nettoyage du disque
if [ "$CLEAN_OPTION" == "1" ]; then
    echo "Nettoyage du disque ${BLOCK_DEVICE} avec des zéros..."
    sudo dd if=/dev/zero of="${BLOCK_DEVICE}" bs=1M status=progress
elif [ "$CLEAN_OPTION" == "2" ]; then
    echo "Nettoyage du disque ${BLOCK_DEVICE} avec des données aléatoires..."
    sudo dd if=/dev/urandom of="${BLOCK_DEVICE}" bs=1M status=progress
else
    echo "Choix invalide. Veuillez relancer le script."
    exit 1
fi

# Partitionnement
if [ "${PART_UEFI}" == "y" ]; then
    # Création des partitions pour le système EFI
    parted -a optimal "${BLOCK_DEVICE}" --script mklabel gpt
    parted -a optimal "${BLOCK_DEVICE}" --script mkpart primary fat32 1MiB "${PART_BOOTEFI_SIZE}MiB"
    parted -a optimal "${BLOCK_DEVICE}" --script set 1 esp on
    parted -a optimal "${BLOCK_DEVICE}" --script mkpart primary ext4 "${PART_BOOTEFI_SIZE}MiB" "${PART_BOOTEFI_SIZE + PART_BOOTMBR_SIZE}MiB"
    parted -a optimal "${BLOCK_DEVICE}" --script mkpart primary ext4 "${PART_BOOTEFI_SIZE + PART_BOOTMBR_SIZE}MiB" "${PART_BOOTEFI_SIZE + PART_BOOTMBR_SIZE + PART_ROOT_SIZE}GiB"
    parted -a optimal "${BLOCK_DEVICE}" --script mkpart primary ext4 "${PART_BOOTEFI_SIZE + PART_BOOTMBR_SIZE + PART_ROOT_SIZE}GiB" 100%

    # Formater les partitions
    mkfs.fat -F32 "${BLOCK_DEVICE}1"  # Partition EFI
    mkfs.ext4 "${BLOCK_DEVICE}2"       # Partition boot
    mkfs.ext4 "${BLOCK_DEVICE}3"       # Partition racine
    mkfs.ext4 "${BLOCK_DEVICE}4"       # Partition home

else
    # Création des partitions pour MBR
    parted -a optimal "${BLOCK_DEVICE}" --script mklabel msdos
    parted -a optimal "${BLOCK_DEVICE}" --script mkpart primary ext4 1MiB "${PART_BOOTMBR_SIZE}MiB"
    parted -a optimal "${BLOCK_DEVICE}" --script mkpart primary ext4 "${PART_BOOTMBR_SIZE}MiB" "${PART_BOOTMBR_SIZE + PART_ROOT_SIZE}GiB"
    parted -a optimal "${BLOCK_DEVICE}" --script mkpart primary ext4 "${PART_BOOTMBR_SIZE + PART_ROOT_SIZE}GiB" 100%

    # Formater les partitions
    mkfs.ext4 "${BLOCK_DEVICE}1"       # Partition boot
    mkfs.ext4 "${BLOCK_DEVICE}2"       # Partition racine
    mkfs.ext4 "${BLOCK_DEVICE}3"       # Partition home
fi

# Créer un fichier swap
fallocate -l "${FILE_SWAP_SIZE}MiB" /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

echo "Partitionnement et formatage terminés avec succès."
