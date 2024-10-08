#!/bin/bash

# Variables
CFG_BLOCK_DEVICE="/dev/sda"
CFG_PART_UEFI="y"            # "y" pour GPT/UEFI, "n" pour MBR/BIOS
CFG_PART_EFI_SIZE="100"      # Taille de la partition EFI en Mo
CFG_PART_SWAP_SIZE="4096"    # Taille de la partition SWAP en Mo
CFG_PART_ROOT_SIZE="100%"     # Taille de la partition ROOT (le reste du disque)

# Supprimer les partitions existantes
echo "Suppression des partitions existantes sur ${CFG_BLOCK_DEVICE}..."
parted ${CFG_BLOCK_DEVICE} mklabel gpt 2>/dev/null || parted ${CFG_BLOCK_DEVICE} mklabel msdos 2>/dev/null

# Vérification du mode UEFI ou BIOS
if [ "${CFG_PART_UEFI}" = "y" ]; then
    echo "Création de partitions en mode GPT pour UEFI..."

    # Créer une nouvelle table de partitions GPT
    parted -a optimal ${CFG_BLOCK_DEVICE} mklabel gpt

    # Créer les partitions
    parted -a optimal ${CFG_BLOCK_DEVICE} mkpart primary fat32 1MiB ${CFG_PART_EFI_SIZE}
    parted -a optimal ${CFG_BLOCK_DEVICE} set 1 esp on  # Définir la partition EFI
    parted -a optimal ${CFG_BLOCK_DEVICE} mkpart primary linux-swap ${CFG_PART_EFI_SIZE} $((CFG_PART_EFI_SIZE + CFG_PART_SWAP_SIZE))
    parted -a optimal ${CFG_BLOCK_DEVICE} mkpart primary ext4 ${CFG_PART_SWAP_SIZE} ${CFG_PART_ROOT_SIZE}

    # Formater les partitions
    mkfs.vfat -F32 ${CFG_BLOCK_DEVICE}1  # Formater la partition EFI
    mkswap ${CFG_BLOCK_DEVICE}2          # Formater la partition SWAP
    mkfs.ext4 -L root-home ${CFG_BLOCK_DEVICE}3  # Formater la partition ROOT/HOME avec le label "root-home"

    # Activer la partition SWAP
    swapon ${CFG_BLOCK_DEVICE}2

    echo "Partitionnement et formatage du disque en mode GPT (UEFI) terminé."

else
    echo "Création de partitions en mode MBR pour BIOS..."

    # Créer une nouvelle table de partitions MBR
    parted -a optimal ${CFG_BLOCK_DEVICE} mklabel msdos

    # Créer les partitions
    parted -a optimal ${CFG_BLOCK_DEVICE} mkpart primary linux-swap 1MiB ${CFG_PART_SWAP_SIZE}
    parted -a optimal ${CFG_BLOCK_DEVICE} mkpart primary ext4 ${CFG_PART_SWAP_SIZE} ${CFG_PART_ROOT_SIZE}
    parted ${CFG_BLOCK_DEVICE} set 2 boot on  # Définir la partition ROOT comme amorçable

    # Formater les partitions
    mkswap ${CFG_BLOCK_DEVICE}1                  # Formater la partition SWAP
    mkfs.ext4 -L root-home ${CFG_BLOCK_DEVICE}2  # Formater la partition ROOT/HOME avec le label "root-home"

    # Activer la partition SWAP
    swapon ${CFG_BLOCK_DEVICE}1

    echo "Partitionnement et formatage du disque en mode MBR (BIOS) terminé."
fi
