#!/bin/bash

# script install.sh

set -e  # Quitte immédiatement en cas d'erreur.

source config.sh # Inclure le fichier de configuration
source fonction.sh  # Charge les fonctions définies dans le fichier fonction.sh.

# Rendre les scripts exécutables.
chmod +x *.sh

# S'assurer que les packages requis sont installés
for pkg in "${packages[@]}"; do
    check_and_install "$pkg"
done

log_msg INFO "Tous les programmes requis sont installés."

# Affiche un message de bienvenue pour l'utilisateur.
log_msg INFO "Bienvenue dans le script d'installation de Gentoo !"


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
export CFG_ROOT_PASSWORD="$(prompt_value "Créer votre mot de passe root -> par défaut : $CFG_ROOT_PASSWORD" "$CFG_ROOT_PASSWORD")"
export CFG_USER="$(prompt_value "Saisir votre nom d'utilisateur -> par exemple :" "$CFG_USER")"
export CFG_USER_PASSWORD="$(prompt_value "Saisir votre mot de passe -> par exemple :" "$CFG_USER_PASSWORD")"


# Affiche la configuration pour validation
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
  - Utilisateur root :         $CFG_ROOT_PASSWORD
  - Votre utilisateur :        $CFG_USER
  - Votre mot de passe :       $CFG_USER_PASSWORD
END
)"

# Demande à l'utilisateur de confirmer la configuration
if ! prompt_confirm "Vérifiez que les informations ci-dessus sont correctes (y/n)"; then
    log_msg WARN "Annulation de l'installation."
    exit 0
fi

# Effacement des systèmes de fichiers existants
if prompt_confirm "Effacer tout sur le périphérique cible ? (y/n)"; then
    log_msg WARN "Exécution de 'wipefs -a $CFG_BLOCK_DEVICE' ..."
    sgdisk --zap-all "$CFG_BLOCK_DEVICE"
    wipefs --force --all "$CFG_BLOCK_DEVICE"
fi    

# Configuration de l'étiquette du disque
if [[ "$CFG_PART_UEFI" == "y" ]]; then
    parted -a optimal "$CFG_BLOCK_DEVICE" mklabel gpt  # GPT pour UEFI
else
    parted -a optimal "$CFG_BLOCK_DEVICE" mklabel msdos  # MBR pour BIOS
fi

# Création des partitions
parted -s "$CFG_BLOCK_DEVICE" mkpart primary 0% "$CFG_PART_BOOT_SIZE"  # Partition boot
parted -s "$CFG_BLOCK_DEVICE" mkpart primary "$CFG_PART_BOOT_SIZE" "$CFG_PART_SWAP_SIZE"  # Partition swap
parted -s "$CFG_BLOCK_DEVICE" mkpart primary "$(($CFG_PART_BOOT_SIZE + $CFG_PART_SWAP_SIZE))" "$CFG_PART_ROOT_SIZE"  # Partition root
parted -s "$CFG_BLOCK_DEVICE" print  # Affiche la table de partitions

# Configuration des systèmes de fichiers
if [[ "$CFG_PART_UEFI" == "y" ]]; then
    mkfs.fat -F32 "${CFG_BLOCK_PART}1"  # FAT32 pour UEFI
else
    mkfs.ext4 "${CFG_BLOCK_PART}1"  # ext4 pour boot
fi
mkswap "${CFG_BLOCK_PART}2"  # Swap
mkfs.ext4 "${CFG_BLOCK_PART}3"  # Root ext4

# Activation de la partition swap
swapon "${CFG_BLOCK_PART}2"

# Montage de la partition root
mkdir -p /mnt/gentoo
mount ${CFG_BLOCK_PART}3 /mnt/gentoo

# Copie et exécution de l'installation du stage3
cp stage3.sh /mnt/gentoo/
cp fonction.sh /mnt/gentoo/
(cd /mnt/gentoo ; bash stage3.sh)

umount -l /mnt/gentoo/dev{/shm,/pts,}  # Démontage des périphériques.
umount -R /mnt/gentoo  # Démontage récursif.

log_msg INFO "Installation terminée. Vous pouvez redémarrer votre machine."
