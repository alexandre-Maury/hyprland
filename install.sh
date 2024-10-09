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
export BLOCK_DEVICE="$(prompt_value "Nom du périphérique cible -> par défaut :" "$BLOCK_DEVICE")"
export PART_UEFI="$(prompt_value "Voulez-vous utiliser le mode UEFI -> par défaut :" "$PART_UEFI")"
export PART_EFI_SIZE="$(prompt_value "Taille de la partition EFI en MiB -> par défaut :" "$PART_EFI_SIZE")"
export PART_BOOT_SIZE="$(prompt_value "Taille de la partition Boot en MiB -> par défaut :" "$PART_BOOT_SIZE")"
export PART_ROOT_SIZE="$(prompt_value "Taille de la partition root en %  -> par défaut :" "$PART_ROOT_SIZE")"
export FILE_SWAP_SIZE="$(prompt_value "Taille du fichier swap en MiB -> par défaut :" "$FILE_SWAP_SIZE")"
export TIMEZONE="$(prompt_value "Fuseau horaire du système -> par défaut :" "$TIMEZONE")"
export LOCALE="$(prompt_value "Locale du système -> par défaut :" "$LOCALE")"
export HOSTNAME="$(prompt_value "Nom d'hôte du système -> par défaut :" "$HOSTNAME")"
export NETWORK_INTERFACE="$(prompt_value "Nom de l'interface réseau -> par défaut :" "$NETWORK_INTERFACE")"
export KEYMAP="$(prompt_value "Disposition du clavier à utiliser -> par défaut :" "$KEYMAP")"
export ROOT_PASSWORD="$(prompt_value "Créer votre mot de passe root -> par défaut : $ROOT_PASSWORD" "$ROOT_PASSWORD")"
export USER="$(prompt_value "Saisir votre nom d'utilisateur -> par exemple :" "$USER")"
export USER_PASSWORD="$(prompt_value "Saisir votre mot de passe -> par exemple :" "$USER_PASSWORD")"

export COMMON_FLAGS
export CPU_FLAGS
export NUM_CORES

# Affiche la configuration pour validation
log_msg INFO "$(cat <<END
Vérification de la configuration :
  - Périphérique cible :       ${BLOCK_DEVICE}
  - UEFI utilisé :             ${PART_UEFI}
  - Taille de l'EFI :          ${PART_EFI_SIZE}MiB
  - Taille de Boot :           ${PART_BOOT_SIZE}MiB 
  - Taille du swap :           ${FILE_SWAP_SIZE}MiB 
  - Taille du root :           ${PART_ROOT_SIZE}%
  - Fuseau horaire :           ${TIMEZONE}
  - Locale :                   ${LOCALE}
  - Nom d'hôte :               ${HOSTNAME}
  - Interface réseau :         ${NETWORK_INTERFACE}
  - Disposition du clavier :   ${KEYMAP}
  - Utilisateur root :         ${ROOT_PASSWORD}
  - Votre utilisateur :        ${USER}
  - Votre mot de passe :       ${USER_PASSWORD}
END
)"

# Demande à l'utilisateur de confirmer la configuration
if ! prompt_confirm "Vérifiez que les informations ci-dessus sont correctes (y/n)"; then
    log_msg WARN "Annulation de l'installation."
    exit 0
fi

# Effacement des systèmes de fichiers existants
if prompt_confirm "Effacer tout sur le périphérique cible ? (y/n)"; then

    log_msg INFO "Début du formatage du disque ${BLOCK_DEVICE}."
    parted ${BLOCK_DEVICE} mklabel gpt 2>/dev/null || parted ${BLOCK_DEVICE} mklabel msdos 2>/dev/null

    

    # Configuration de l'étiquette du disque
    if [[ "$PART_UEFI" == "y" ]]; then

        log_msg INFO "Début du partitionnement du disque ${BLOCK_DEVICE} en UEFI."
        parted -a optimal ${BLOCK_DEVICE} --script mklabel gpt
        parted -a optimal ${BLOCK_DEVICE} --script mkpart primary fat32 1MiB ${PART_EFI_SIZE}MiB
        parted -a optimal ${BLOCK_DEVICE} --script set 1 esp on 
        parted -a optimal ${BLOCK_DEVICE} --script mkpart primary ext4 ${PART_EFI_SIZE}MiB $((PART_EFI_SIZE + PART_BOOT_SIZE))MiB 
    else

        log_msg INFO "Début du partitionnement du disque ${BLOCK_DEVICE} en MBR."
        parted -a optimal ${BLOCK_DEVICE} --script mklabel msdos
        parted -a optimal ${BLOCK_DEVICE} --script mkpart primary ext4 1MiB ${PART_BOOT_SIZE}MiB 
        parted -a optimal ${BLOCK_DEVICE} --script set 1 boot on 
    fi


    # Création de la partition ROOT
    parted -a optimal ${BLOCK_DEVICE} --script mkpart primary ext4 $((PART_EFI_SIZE + PART_BOOT_SIZE))MiB ${PART_ROOT_SIZE}%  


    # Configuration des systèmes de fichiers
    if [[ "$PART_UEFI" == "y" ]]; then
        # Formater les partitions
        mkfs.vfat -F32 ${BLOCK_DEVICE}1                 # EFI partition
        mkfs.ext4 -L boot ${BLOCK_DEVICE}2              # Boot partition
        mkfs.ext4 -L root-home ${BLOCK_DEVICE}3         # Root partition

        # Monter les partitions
        mkdir -p /mnt/gentoo
        mount ${BLOCK_DEVICE}3 /mnt/gentoo              # Monter la partition racine

        mkdir -p /mnt/gentoo/boot  
        mount ${BLOCK_DEVICE}2 /mnt/gentoo/boot         # Monter la partition boot

        mkdir -p /mnt/gentoo/boot/EFI      
        mount ${BLOCK_DEVICE}1 /mnt/gentoo/boot/EFI     # Monter la partition EFI
    else
        # Formater les partitions
        mkfs.ext4 -L boot ${BLOCK_DEVICE}1              # Boot partition
        mkfs.ext4 -L root-home ${BLOCK_DEVICE}2         # Root partition

        mkdir -p /mnt/gentoo
        mount ${BLOCK_DEVICE}2 /mnt/gentoo              # Monter la partition racine

        mkdir -p /mnt/gentoo/boot  
        mount ${BLOCK_DEVICE}1 /mnt/gentoo/boot         # Monter la partition boot
    fi

    # Formater et créer le fichier swap
    dd if=/dev/zero of=/mnt/gentoo/swap bs=1G count=${FILE_SWAP_SIZE}/1024   
    chmod 600 /mnt/gentoo/swap                            
    mkswap /mnt/gentoo/swap                                
    swapon /mnt/gentoo/swap    


    log_msg INFO "Partitionnement et formatage du disque terminés avec succès."
    parted -s "$BLOCK_DEVICE" print  # Affiche la table de partitions
fi    

# Copie et exécution de l'installation du stage3
if [ -d "/mnt/gentoo" ]; then
    
    cp stage3.sh /mnt/gentoo/
    cp fonction.sh /mnt/gentoo/
    cp config.sh /mnt/gentoo/
    
    # Exécution du script stage3.sh dans /mnt/gentoo
    (cd /mnt/gentoo && bash stage3.sh)
else
    echo "Erreur : le répertoire /mnt/gentoo n'existe pas."
    exit 1
fi

umount -R /mnt/gentoo  # Démontage récursif.

log_msg INFO "Installation terminée. Vous pouvez redémarrer votre machine."
log_msg INFO "Aprés redémarrage -> eselect locale list"
log_msg INFO "Aprés redémarrage -> hostnamectl"


