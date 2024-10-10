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

if [[ "$PART_UEFI" == "y" ]]; then
    export PART_BOOTEFI_SIZE="$(prompt_value "Taille de la partition EFI en MiB -> par défaut :" "$PART_BOOTEFI_SIZE")"
else
    export PART_BOOTMBR_SIZE="$(prompt_value "Taille de la partition BOOT en MiB -> par défaut :" "$PART_BOOTMBR_SIZE")"
fi

export PART_ROOT_SIZE="$(prompt_value "Taille de la partition Racine en GiB -> par défaut :" "$PART_ROOT_SIZE")"
export PART_HOME_SIZE="$(prompt_value "Taille de la partition Home en %  -> par défaut :" "$PART_HOME_SIZE")"
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


clear
log_msg INFO "Vérification de la configuration :"
echo ""
log_msg "- Périphérique cible"                            "${BLOCK_DEVICE}"
log_msg "- UEFI Activé"                                   "${PART_UEFI}"

if [[ "$PART_UEFI" == "y" ]]; then
    log_msg "- Taille de la partition boot EFI en MiB"    "${PART_BOOTEFI_SIZE}MiB"
else
    log_msg "- Taille de la partition boot MBR en MiB"    "${PART_BOOTMBR_SIZE}MiB"
fi

log_msg "- Taille de la partition Racine en GiB"          "${PART_ROOT_SIZE}GiB"
log_msg "- Taille de la partition Home en %"              "${PART_HOME_SIZE}%"
log_msg "- Taille du fichier swap en MiB"                 "${FILE_SWAP_SIZE}MiB"
log_msg "- Fuseau horaire"                                "${TIMEZONE}"
log_msg "- Locale"                                        "${LOCALE}"
log_msg "- Nom d'hôte"                                    "${HOSTNAME}"
log_msg "- Interface réseau"                              "${NETWORK_INTERFACE}"
log_msg "- Disposition du clavier"                        "${KEYMAP}"
log_msg "- Votre mot de passe ROOT"                       "${ROOT_PASSWORD}"
log_msg "- Votre utilisateur"                             "${USER}"
log_msg "- Votre mot de passe"                            "${USER_PASSWORD}"
echo ""
# Demande à l'utilisateur de confirmer la configuration
if ! prompt_confirm "Vérifiez que les informations ci-dessus sont correctes (Y/n)"; then
    log_msg WARN "Annulation de l'installation."
    exit 0
fi

# Effacement des systèmes de fichiers existants
if prompt_confirm "Effacer tout sur le périphérique cible ? (y/n)"; then

    # Vérifier si le disque existe
    if [ ! -b "${BLOCK_DEVICE}" ]; then
        log_msg WARN "Le disque ${BLOCK_DEVICE} n'existe pas."
        exit 1
    fi

    # Choisir le type de nettoyage
    log_msg INFO "Choisissez le type de nettoyage du disque ${BLOCK_DEVICE} :"
    echo "1. Nettoyage avec des zéros"
    echo "2. Nettoyage avec des données aléatoires"
    read -rp "Entrez votre choix (1 ou 2) : " CLEAN_OPTION

    # Nettoyage du disque
    if [ "$CLEAN_OPTION" == "1" ]; then
        log_msg INFO "Nettoyage du disque ${BLOCK_DEVICE} avec des zéros..."
        dd if=/dev/zero of="${BLOCK_DEVICE}" bs=1M status=progress
    elif [ "$CLEAN_OPTION" == "2" ]; then
        log_msg INFO "Nettoyage du disque ${BLOCK_DEVICE} avec des données aléatoires..."
        dd if=/dev/urandom of="${BLOCK_DEVICE}" bs=1M status=progress
    else
        log_msg WARN "Choix invalide. Veuillez relancer le script."
        exit 1
    fi

    log_msg INFO "Nettoyage du disque ${BLOCK_DEVICE} terminée."

    # Conversion de PART_ROOT_SIZE de GiB en MiB
    PART_ROOT_SIZE_MB=$((PART_ROOT_SIZE * 1024))

    # Configuration du Disque
    if [[ "$PART_UEFI" == "y" ]]; then
        parted -a optimal "${BLOCK_DEVICE}" --script mklabel gpt
        parted -a optimal "${BLOCK_DEVICE}" --script mkpart primary fat32 1MiB ${PART_BOOTEFI_SIZE}MiB # Partition EFI
        parted -a optimal "${BLOCK_DEVICE}" --script set 1 esp on 
        parted -a optimal "${BLOCK_DEVICE}" --script mkpart primary ext4 ${PART_BOOTEFI_SIZE}MiB $((PART_BOOTEFI_SIZE + PART_ROOT_SIZE_MB))MiB # Partition Racine
        parted -a optimal "${BLOCK_DEVICE}" --script mkpart primary ext4 $((PART_BOOTEFI_SIZE + PART_ROOT_SIZE_MB))MiB ${PART_HOME_SIZE}% # Partition Home

        mkfs.vfat -F32 "${BLOCK_DEVICE}1"               # Partition EFI
        mkfs.ext4 -L Racine "${BLOCK_DEVICE}2"          # Partition Racine
        mkfs.ext4 -L Home "${BLOCK_DEVICE}3"            # Partition Home

        # Monter les partitions
        mkdir -p /mnt
        mount ${BLOCK_DEVICE}2 /mnt              # Monter la partition racine

        mkdir -p /mnt/{home,boot}
        mount ${BLOCK_DEVICE}3 /mnt/home         # Monter la partition boot  
        mount ${BLOCK_DEVICE}1 /mnt/boot         # Monter la partition EFI

    else
        parted -a optimal "${BLOCK_DEVICE}" --script mklabel msdos
        parted -a optimal "${BLOCK_DEVICE}" --script mkpart primary ext4 1MiB ${PART_BOOTMBR_SIZE}MiB # Partition MBR
        parted -a optimal "${BLOCK_DEVICE}" --script set 1 boot on 
        parted -a optimal "${BLOCK_DEVICE}" --script mkpart primary ext4 ${PART_BOOTMBR_SIZE}MiB $((PART_BOOTMBR_SIZE + PART_ROOT_SIZE_MB))MiB # Partition Racine
        parted -a optimal "${BLOCK_DEVICE}" --script mkpart primary ext4 $((PART_BOOTMBR_SIZE + PART_ROOT_SIZE_MB))MiB ${PART_HOME_SIZE}% # Partition Home

        mkfs.ext4 -L Boot "${BLOCK_DEVICE}1"            # Partition MBR
        mkfs.ext4 -L Racine "${BLOCK_DEVICE}2"          # Partition Racine
        mkfs.ext4 -L Home"${BLOCK_DEVICE}3"             # Partition Home

        mkdir -p /mnt
        mount ${BLOCK_DEVICE}2 /mnt              # Monter la partition boot

        mkdir -p /mnt/{home,boot}
        mount ${BLOCK_DEVICE}3 /mnt/home         # Monter la partition home
        mount ${BLOCK_DEVICE}1 /mnt/boot         # Monter la partition racine

    fi

    # Formater et créer le fichier swap
    dd if=/dev/zero of=/mnt/swap bs=1M count=${FILE_SWAP_SIZE}  
    chmod 600 /mnt/swap                            
    mkswap /mnt/swap                                
    swapon /mnt/swap    


    log_msg INFO "Partitionnement et formatage du disque terminés avec succès."
    parted -s "$BLOCK_DEVICE" print  # Affiche la table de partitions
fi    

# Copie et exécution de l'installation du stage3
if [ -d "/mnt" ]; then
    
    cp stage3.sh /mnt
    cp fonction.sh /mnt
    cp config.sh /mnt
    
    # Exécution du script stage3.sh dans /mnt/gentoo
    (cd /mnt && bash stage3.sh)
else
    echo "Erreur : le répertoire /mnt n'existe pas."
    exit 1
fi

umount -R /mnt  # Démontage récursif.

log_msg INFO "Installation terminée. Vous pouvez redémarrer votre machine."
log_msg INFO "Aprés redémarrage -> eselect locale list"
log_msg INFO "Aprés redémarrage -> hostnamectl"
log_msg INFO "Aprés redémarrage -> passwd" # Set root password