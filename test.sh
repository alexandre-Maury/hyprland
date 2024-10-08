#!/bin/bash

# Variables
CFG_BLOCK_DEVICE="/dev/sda"
CFG_PART_UEFI="y"
CFG_PART_EFI_SIZE="100"     # 100 Mo
CFG_PART_ROOT_SIZE="100%"    # Le reste

# Effacement des systèmes de fichiers existants
if prompt_confirm "Effacer tout sur le périphérique cible ? (y/n)"; then
  parted ${CFG_BLOCK_DEVICE} mklabel gpt 2>/dev/null || parted ${CFG_BLOCK_DEVICE} mklabel msdos 2>/dev/null
fi    

# Configuration de l'étiquette du disque
if [[ "$CFG_PART_UEFI" == "y" ]]; then
    parted -a optimal ${CFG_BLOCK_DEVICE} --script mklabel gpt
    parted -a optimal ${CFG_BLOCK_DEVICE} --script mkpart primary fat32 1MiB ${CFG_PART_EFI_SIZE}MiB
    parted -a optimal ${CFG_BLOCK_DEVICE} --script set 1 esp on  # Définir la partition EFI
else
    parted -a optimal ${CFG_BLOCK_DEVICE} --script mklabel msdos
    parted -a optimal ${CFG_BLOCK_DEVICE} --script mkpart primary ext4 1MiB ${CFG_PART_EFI_SIZE}MiB # Partition Boot
    parted -a optimal ${CFG_BLOCK_DEVICE} --script set 1 boot on # Définir la partition boot comme amorçable
fi

# Création des partitions
parted -a optimal ${CFG_BLOCK_DEVICE} --script mkpart primary ext4 $((CFG_PART_EFI_SIZE))MiB ${CFG_PART_ROOT_SIZE}  # Partition ROOT

# Configuration des systèmes de fichiers
if [[ "$CFG_PART_UEFI" == "y" ]]; then
    mkfs.vfat -F32 ${CFG_BLOCK_DEVICE}1      
else
    mkfs.ext4 -L boot ${CFG_BLOCK_DEVICE}1    
fi

# Formater et créer le fichier swap
dd if=/dev/zero of=/mnt/gentoo/swap bs=1G count=4   # Créer un fichier swap de 4 Go
chmod 600 /mnt/gentoo/swap                             # Configurer les droits
mkswap /mnt/gentoo/swap                                # Formater le fichier swap
swapon /mnt/gentoo/swap                                # Activer le swap

mkfs.ext4 -L root-home ${CFG_BLOCK_DEVICE}2             # Formater la partition ROOT avec le label "root-home"

log_msg INFO "Partitionnement et formatage du disque terminés avec succès."
parted -s "$CFG_BLOCK_DEVICE" print  # Affiche la table de partitions
