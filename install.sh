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
export CFG_PART_UEFI="$(prompt_value "Voulez-vous utiliser le mode UEFI -> par défaut :" "$CFG_PART_UEFI")"
export CFG_PART_EFI_SIZE="$(prompt_value "Taille de la partition boot|EFI en Mo -> par défaut :" "$CFG_PART_EFI_SIZE")"
export CFG_FILE_SWAP_SIZE="$(prompt_value "Taille de la partition swap en Mo -> par défaut :" "$CFG_FILE_SWAP_SIZE")"
export CFG_PART_ROOT_SIZE="$(prompt_value "Taille de la partition root en %  -> par défaut :" "$CFG_PART_ROOT_SIZE")"
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
  - UEFI utilisé :             $CFG_PART_UEFI
  - Taille de boot :           $CFG_PART_EFI_SIZE
  - Taille du swap :           $CFG_FILE_SWAP_SIZE
  - Taille du root :           $CFG_PART_ROOT_SIZE
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
           
mkfs.ext4 -L root-home ${CFG_BLOCK_DEVICE}2

mkdir -p /mnt/gentoo
mount ${CFG_BLOCK_DEVICE}2 /mnt/gentoo

if [[ "$CFG_PART_UEFI" == "y" ]]; then
    mkdir -p /mnt/gentoo/boot/EFI      
    mount ${CFG_BLOCK_DEVICE}1 /mnt/gentoo/boot/EFI
else
    mkdir -p /mnt/gentoo/boot
    mount ${CFG_BLOCK_DEVICE}1 /mnt/gentoo/boot
fi

# Formater et créer le fichier swap
dd if=/dev/zero of=/mnt/gentoo/swap bs=1G count=${CFG_FILE_SWAP_SIZE}   # Créer un fichier swap de 4 Go
chmod 600 /mnt/gentoo/swap                             # Configurer les droits
mkswap /mnt/gentoo/swap                                # Formater le fichier swap
swapon /mnt/gentoo/swap    


log_msg INFO "Partitionnement et formatage du disque terminés avec succès."
parted -s "$CFG_BLOCK_DEVICE" print  # Affiche la table de partitions

# Copie et exécution de l'installation du stage3
cp stage3.sh /mnt/gentoo/
cp fonction.sh /mnt/gentoo/
cp config.sh /mnt/gentoo/
(cd /mnt/gentoo ; bash stage3.sh)

umount -R /mnt/gentoo  # Démontage récursif.

log_msg INFO "Installation terminée. Vous pouvez redémarrer votre machine."
log_msg INFO "Aprés redémarrage -> eselect locale list"
log_msg INFO "Aprés redémarrage -> hostnamectl"


