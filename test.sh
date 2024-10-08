#!/bin/bash

# Variables
DISK="/dev/sda"
CFG_PART_EFI_SIZE="100"     # 100 Mo
CFG_PART_SWAP_SIZE="4096"    # 4096 Mo
CFG_PART_ROOT_SIZE="71680"   # 70 Go
CFG_PART_HOME_SIZE="100%"    # Le reste

# Supprimer les partitions existantes
sgdisk -Z ${DISK}

# Créer la table de partitions GPT
sgdisk -og ${DISK}

# Créer la partition EFI
sgdisk -n 1:0:+${CFG_PART_EFI_SIZE}M -t 1:ef00 ${DISK}

# Créer la partition SWAP
sgdisk -n 2:0:+${CFG_PART_SWAP_SIZE}M -t 2:8200 ${DISK}

# Créer la partition ROOT
sgdisk -n 3:0:+${CFG_PART_ROOT_SIZE}M -t 3:8300 ${DISK}

# Créer la partition HOME (tout l'espace restant)
sgdisk -n 4:0:0 -t 4:8302 ${DISK}

# Formater les partitions
mkfs.vfat -F32 ${DISK}1  # Partition EFI
mkswap ${DISK}2           # Partition SWAP
mkfs.ext4 ${DISK}3        # Partition ROOT
mkfs.ext4 ${DISK}4        # Partition HOME

# Activer la partition SWAP
swapon ${DISK}2

echo "Partitionnement et formatage de ${DISK} terminé."
