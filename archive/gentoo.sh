#!/bin/bash

# Définir les variables de configuration
ARCH="amd64" # Architecture du système
TZ="Europe/Paris" # Timezone
LANG="fr_FR.UTF-8" # Langue
HARDDISK="/dev/sda" # Disque dur

# Fonction pour gérer les options de configuration
# Cette fonction permet de définir les options de configuration du système
# Elle prend en paramètre le nom de l'option et la valeur à attribuer
function set_config() {
    # Utiliser un case pour déterminer quelle option est définie
    case $1 in
        ARCH)
            # Définir l'architecture du système
            ARCH=$2
            ;;
        TZ)
            # Définir la timezone du système
            TZ=$2
            ;;
        LANG)
            # Définir la langue du système
            LANG=$2
            ;;
        HARDDISK)
            # Définir le disque dur du système
            HARDDISK=$2
            ;;
    esac
}

# Fonction pour gérer les partitions du disque dur
# Cette fonction permet de créer les partitions nécessaires pour l'installation de Gentoo
# Elle utilise la commande parted pour créer les partitions
function set_partitions() {
    # Afficher un message pour indiquer que les partitions sont en cours de création
    echo "Création des partitions..."
    
    # Utiliser la commande parted pour créer les partitions
    # La commande mklabel gpt crée un label GPT sur le disque dur
    parted --script "$HARDDISK" mklabel gpt
    
    # La commande mkpart crée une partition sur le disque dur
    # La partition est créée avec le système de fichiers ext4
    parted --script "$HARDDISK" mkpart primary ext4 1MiB 512MiB
    parted --script "$HARDDISK" mkpart primary ext4 512MiB 100%
    parted --script "$HARDDISK" mkpart primary linux-swap 0% 512MiB
    
    # La commande set permet de définir les propriétés des partitions
    # L'option lvm on permet d'activer le gestionnaire de volumes logiques
    parted --script "$HARDDISK" set 1 lvm on
    parted --script "$HARDDISK" set 2 lvm on
    parted --script "$HARDDISK" set 3 lvm on
    
    # La commande print permet d'afficher les informations sur les partitions
    parted --script "$HARDDISK" print
    
    # La commande mkfs permet de formater les partitions
    # La commande mkfs.vfat permet de formater une partition avec le système de fichiers vfat
    mkfs.vfat -F 32 "$HARDDISK"1
    
    # La commande mkfs.ext4 permet de formater une partition avec le système de fichiers ext4
    mkfs.ext4 -F "$HARDDISK"2
    
    # La commande mkswap permet de formater une partition pour le swap
    mkswap "$HARDDISK"3
    
    # La commande swapon permet d'activer le swap
    swapon "$HARDDISK"3
    
    # La commande mount permet de monter les partitions
    mount "$HARDDISK"2 /mnt
    mkdir /mnt/boot
    mount "$HARDDISK"1 /mnt/boot
}

# Fonction pour installer Gentoo avec systemd
# Cette fonction installe Gentoo avec systemd sur ton système
function install_gentoo_systemd() {
    # Définir les options de configuration
    set_config ARCH "$ARCH"
    set_config TZ "$TZ"
    set_config LANG "$LANG"
    set_config HARDDISK "$HARDDISK"
    
    # Créer les partitions sur le disque dur
    set_partitions
    
    # Télécharger le fichier d'installation de Gentoo
    curl -O "https://mirror.globo.tech/gentoo/releases/amd64/autobuilds/latest-i686/install-medium.iso"
    
    # Générer le noyau de Gentoo avec systemd
    genkernel --install "https://mirror.globo.tech/gentoo/releases/amd64/autobuilds/latest-i686/install-medium.iso" --kernel-config=/path/to/kernel-config --makeopts="-j$(nproc)" --bootloader/grub/device="/dev/sda" --affinity=systemd
}

# Fonction principale du script
# Cette fonction appelle la fonction install_gentoo_systemd
function main() {
    # Appeler la fonction install_gentoo_systemd
    install_gentoo_systemd
}

# Appeler la fonction principale du script
main