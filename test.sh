#!/bin/bash

# Variables
DISK="/dev/sda"
CFG_PART_UEFI="y"            # "y" pour GPT/UEFI, "n" pour MBR/BIOS
CFG_PART_EFI_SIZE="100M"      # Taille de la partition EFI en Mo
CFG_PART_SWAP_SIZE="4096M"    # Taille de la partition SWAP en Mo
CFG_PART_ROOT_SIZE="100%"     # Taille de la partition ROOT (le reste du disque)

# Supprimer les partitions existantes
echo "Suppression des partitions existantes sur ${DISK}..."
parted ${DISK} mklabel gpt 2>/dev/null || parted ${DISK} mklabel msdos 2>/dev/null

# Vérification du mode UEFI ou BIOS
if [ "${CFG_PART_UEFI}" = "y" ]; then
    echo "Création de partitions en mode GPT pour UEFI..."

    # Créer une nouvelle table de partitions GPT
    parted ${DISK} mklabel gpt

    # Créer les partitions
    parted -a optimal ${DISK} mkpart primary fat32 1MiB ${CFG_PART_EFI_SIZE}
    parted -a optimal ${DISK} set 1 esp on  # Définir la partition EFI
    parted -a optimal ${DISK} mkpart primary linux-swap ${CFG_PART_EFI_SIZE} $((CFG_PART_EFI_SIZE + CFG_PART_SWAP_SIZE))
    parted -a optimal ${DISK} mkpart primary ext4 ${CFG_PART_SWAP_SIZE} ${CFG_PART_ROOT_SIZE}

    # Formater les partitions
    mkfs.vfat -F32 ${DISK}1  # Formater la partition EFI
    mkswap ${DISK}2          # Formater la partition SWAP
    mkfs.ext4 -L root-home ${DISK}3  # Formater la partition ROOT/HOME avec le label "root-home"

    # Activer la partition SWAP
    swapon ${DISK}2

    echo "Partitionnement et formatage du disque en mode GPT (UEFI) terminé."

else
    echo "Création de partitions en mode MBR pour BIOS..."

    # Créer une nouvelle table de partitions MBR
    parted ${DISK} mklabel msdos

    # Créer les partitions
    parted -a optimal ${DISK} mkpart primary linux-swap 1MiB ${CFG_PART_SWAP_SIZE}
    parted -a optimal ${DISK} mkpart primary ext4 ${CFG_PART_SWAP_SIZE} ${CFG_PART_ROOT_SIZE}
    parted ${DISK} set 2 boot on  # Définir la partition ROOT comme amorçable

    # Formater les partitions
    mkswap ${DISK}1                  # Formater la partition SWAP
    mkfs.ext4 -L root-home ${DISK}2  # Formater la partition ROOT/HOME avec le label "root-home"

    # Activer la partition SWAP
    swapon ${DISK}1

    echo "Partitionnement et formatage du disque en mode MBR (BIOS) terminé."
fi
