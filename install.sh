#!/bin/bash
set -e  # Quitte immédiatement en cas d'erreur.

source funcs.sh  # Charge les fonctions définies dans le fichier funcs.sh.

# Affiche un message de bienvenue pour l'utilisateur.
log_msg INFO "Bienvenue dans le script d'installation simple de Gentoo !"
log_msg INFO "$(cat <<-END
Ce script suppose les éléments suivants :
  - le réseau fonctionne
  - GPT et UEFI sont utilisés
  - des systèmes de fichiers ext4
  - OpenRC est le gestionnaire de services
END
)"

#
# Installation initiale
#

# S'assure que tous les scripts sont exécutables.
chmod +x *.sh

# Récupération du nom du disque
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
CFG_LOCALE="fr_FR"
CFG_HOSTNAME="gentoo"
CFG_NETWORK_INTERFACE="enp0s3"
CFG_KEYMAP="fr"



# Configuration de l'installateur
export CFG_BLOCK_DEVICE="$(prompt_value "Nom du périphérique cible -> par défaut :" "$CFG_BLOCK_DEVICE")"
export CFG_PART_PREFIX="$(prompt_value "Préfixe de la partition -> [p] pour les disques NVMe - [] pour les HDD/SSD" "$CFG_PART_PREFIX")"
export CFG_BLOCK_PART="${CFG_BLOCK_DEVICE}${CFG_PART_PREFIX}"
export CFG_PART_UEFI="$(prompt_value "Voulez-vous utiliser le mode UEFI -> par défaut :" "$CFG_PART_UEFI")"
export CFG_PART_BOOT_SIZE="$(prompt_value "Taille de la partition boot en Mo -> par défaut :" "$CFG_PART_BOOT_SIZE")"
export CFG_PART_SWAP_SIZE="$(prompt_value "Taille de la partition swap en Mo -> par défaut :" "$CFG_PART_SWAP_SIZE")"
export CFG_PART_ROOT_SIZE="$(prompt_value "Taille de la partition root en %  -> par défaut :" "$CFG_PART_ROOT_SIZE")"
export CFG_MUSL="$(prompt_value "Utiliser MUSL au lieu de la bibliothèque C GNU -> par défaut :" "$CFG_MUSL")"
export CFG_LLVM="$(prompt_value "Utiliser LLVM au lieu de GCC -> par défaut :" "$CFG_LLVM")"
export CFG_TIMEZONE="$(prompt_value "Fuseau horaire du système -> par défaut :" "$CFG_TIMEZONE")"
export CFG_LOCALE="$(prompt_value "Locale du système -> par défaut :" "$CFG_LOCALE")"
export CFG_HOSTNAME="$(prompt_value "Nom d'hôte du système -> par défaut :" "$CFG_HOSTNAME")"
export CFG_NETWORK_INTERFACE="$(prompt_value "Nom de l'interface réseau -> par défaut :" "$CFG_NETWORK_INTERFACE")"
export CFG_KEYMAP="$(prompt_value "Disposition du clavier à utiliser -> par défaut :" "$CFG_KEYMAP")"
export CFG_ROOT_PASSWORD="$(prompt_value "Créer votre Mot de passe utilisateur root" "")"

# Affiche la configuration pour que l'utilisateur la valide.
log_msg INFO "$(cat <<END
Vérification de la configuration :
  - Périphérique cible :       $CFG_BLOCK_DEVICE
  - Préfixe de partition :     $CFG_PART_PREFIX
  - Partition :                $CFG_BLOCK_PART
  - UEFI utilisé :             $CFG_PART_UEFI
  - Taille de boot :           $CFG_PART_BOOT_SIZE
  - Taille du swap :           $CFG_PART_SWAP_SIZE
  - Taille du root :           $CFG_PART_ROOT_SIZE
  - MUSL utilisé :             $CFG_MUSL
  - LLVM utilisé :             $CFG_LLVM
  - Fuseau horaire :           $CFG_TIMEZONE
  - Locale :                   $CFG_LOCALE
  - Nom d'hôte :               $CFG_HOSTNAME
  - Interface réseau :         $CFG_NETWORK_INTERFACE
  - Disposition du clavier :   $CFG_KEYMAP
  - Mot de passe root :        $CFG_ROOT_PASSWORD
END
)"

# Demande à l'utilisateur de confirmer la configuration.
PROMPT_PROCEED=$(prompt_accept "Vérifiez que les informations ci-dessus sont correctes - y/n")
if [[ "$PROMPT_PROCEED" == "n" ]]; then
  log_msg WARN "Quitter l'installateur en toute sécurité, rien n'a été fait..."
  exit 0
fi

# Effacement des anciens systèmes de fichiers
PROMPT_WIPEFS=$(prompt_accept "Effacer tout sur le système de fichiers cible - y/n")
if [[ "$PROMPT_WIPEFS" == "y" ]]; then
  log_msg WARN "Exécution de 'wipefs -a $CFG_BLOCK_DEVICE' ..."
  wipefs -a $CFG_BLOCK_DEVICE
fi

# Configuration de l'étiquette du disque
if [[ "${CFG_PART_UEFI}" == "y" ]]; then
  parted -a optimal $CFG_BLOCK_DEVICE mklabel gpt  # Utilise GPT si UEFI est sélectionné.
else
  parted -a optimal $CFG_BLOCK_DEVICE mklabel msdos  # Utilise MBR sinon.
fi

# Création des partitions
parted -s $CFG_BLOCK_DEVICE mkpart primary 0% $CFG_PART_BOOT_SIZE  # Partition de boot.
parted -s $CFG_BLOCK_DEVICE mkpart primary $CFG_PART_BOOT_SIZE $CFG_PART_SWAP_SIZE  # Partition swap.
parted -s $CFG_BLOCK_DEVICE mkpart primary $(($CFG_PART_BOOT_SIZE+$CFG_PART_SWAP_SIZE)) $CFG_PART_ROOT_SIZE  # Partition root.
parted -s $CFG_BLOCK_DEVICE print  # Affiche la table de partitionnement.

# Configuration des systèmes de fichiers
if [[ "${CFG_PART_UEFI}" == "y" ]]; then
  mkfs.fat -F 32 ${CFG_BLOCK_PART}1  # Crée un système de fichiers FAT32 pour UEFI.
else
  mkfs.ext4 ${CFG_BLOCK_PART}1  # Crée un système de fichiers ext4 pour le boot.
fi
mkswap ${CFG_BLOCK_PART}2  # Crée le swap.
mkfs.ext4 ${CFG_BLOCK_PART}3  # Crée un système de fichiers ext4 pour la partition root.

# Active la partition swap
swapon ${CFG_BLOCK_PART}2

# Monte la partition root
mkdir -p /mnt/gentoo
mount ${CFG_BLOCK_PART}3 /mnt/gentoo

# Exécute l'installation du stage3
cp stage3.sh /mnt/gentoo/
cp funcs.sh /mnt/gentoo/
(cd /mnt/gentoo ; bash stage3.sh)

# Finalise l'installation
umount -l /mnt/gentoo/dev{/shm,/pts,}  # Démontage des périphériques.
umount -R /mnt/gentoo  # Démontage récursif.

log_msg INFO "Tout est terminé ! Vous pouvez exécuter 'reboot' maintenant !"  # Message final.
