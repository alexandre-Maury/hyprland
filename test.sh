#!/bin/bash

# Variables
CFG_BLOCK_DEVICE="/dev/sda"
CFG_PART_UEFI="y"            # "y" pour GPT/UEFI, "n" pour MBR/BIOS
CFG_PART_EFI_SIZE="100"      # Taille de la partition EFI en Mo
CFG_PART_SWAP_SIZE="4096"    # Taille de la partition SWAP en Mo
CFG_PART_ROOT_SIZE="100%"    # Taille de la partition ROOT (le reste du disque)

# Supprimer les partitions existantes
echo "Suppression des partitions existantes sur ${CFG_BLOCK_DEVICE}..."
parted ${CFG_BLOCK_DEVICE} --script mklabel gpt 2>/dev/null || parted ${CFG_BLOCK_DEVICE} --script mklabel msdos 2>/dev/null

# Vérification du mode UEFI ou BIOS
if [ "${CFG_PART_UEFI}" = "y" ]; then
    echo "Création de partitions en mode GPT pour UEFI..."

    # Créer une nouvelle table de partitions GPT
    parted -a optimal ${CFG_BLOCK_DEVICE} --script mklabel gpt

    # Créer les partitions
    parted -a optimal ${CFG_BLOCK_DEVICE} --script mkpart primary fat32 1MiB ${CFG_PART_EFI_SIZE}MiB
    parted -a optimal ${CFG_BLOCK_DEVICE} --script set 1 esp on  # Définir la partition EFI
    parted -a optimal ${CFG_BLOCK_DEVICE} --script mkpart primary linux-swap ${CFG_PART_EFI_SIZE}MiB $((CFG_PART_EFI_SIZE + CFG_PART_SWAP_SIZE))MiB
    parted -a optimal ${CFG_BLOCK_DEVICE} --script mkpart primary ext4 $((CFG_PART_EFI_SIZE + CFG_PART_SWAP_SIZE))MiB ${CFG_PART_ROOT_SIZE}

    # Formater les partitions
    mkfs.vfat -F32 ${CFG_BLOCK_DEVICE}1  # Formater la partition EFI
    mkswap ${CFG_BLOCK_DEVICE}2          # Formater la partition SWAP
    mkfs.ext4 -L root-home ${CFG_BLOCK_DEVICE}3  # Formater la partition ROOT/HOME avec le label "root-home"

    # Activer la partition SWAP
    swapon ${CFG_BLOCK_DEVICE}2

    echo "Partitionnement et formatage du disque en mode GPT (UEFI) terminé."

else
    echo "Création de partitions en mode MBR pour BIOS avec partition boot..."

    # Créer une nouvelle table de partitions MBR
    parted -a optimal ${CFG_BLOCK_DEVICE} --script mklabel msdos

    # Créer les partitions
    parted -a optimal ${CFG_BLOCK_DEVICE} --script mkpart primary ext4 1MiB ${CFG_PART_EFI_SIZE}MiB      # Partition Boot
    parted -a optimal ${CFG_BLOCK_DEVICE} --script set 1 boot on # Définir la partition boot comme amorçable
    parted -a optimal ${CFG_BLOCK_DEVICE} --script mkpart primary linux-swap ${CFG_PART_EFI_SIZE}MiB $((CFG_PART_EFI_SIZE + CFG_PART_SWAP_SIZE))MiB  # Partition SWAP
    parted -a optimal ${CFG_BLOCK_DEVICE} --script mkpart primary ext4 $((CFG_PART_EFI_SIZE + CFG_PART_SWAP_SIZE))MiB ${CFG_PART_ROOT_SIZE}  # Partition ROOT

    # Formater les partitions
    mkfs.ext4 -L boot ${CFG_BLOCK_DEVICE}1                  # Formater la partition boot
    mkswap ${CFG_BLOCK_DEVICE}2                             # Formater la partition SWAP
    mkfs.ext4 -L root-home ${CFG_BLOCK_DEVICE}3             # Formater la partition ROOT avec le label "root-home"

    # Activer la partition SWAP
    swapon ${CFG_BLOCK_DEVICE}2

    echo "Partitionnement et formatage du disque en mode MBR (BIOS) avec partition boot terminé."
fi
