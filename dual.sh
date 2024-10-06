#!/bin/bash

# Vérifier si le script est exécuté avec des privilèges root
if [[ $EUID -ne 0 ]]; then
   echo "Ce script doit être exécuté en tant que root." 
   exit 1
fi

# Détection automatique du disque principal (en excluant les périphériques amovibles)
DISK=$(lsblk -nd --output NAME,SIZE,TYPE | grep "disk" | sort -k2 -h | tail -n 1 | awk '{print "/dev/" $1}')
echo "Disque détecté : $DISK"

# Vérification de l'existence de Windows
WIN_PART=$(lsblk -f | grep -i ntfs | awk '{print $1}')
if [[ -n $WIN_PART ]]; then
    echo "Partition Windows détectée : /dev/$WIN_PART"
else
    echo "Aucune partition Windows détectée. Continuer sans Windows ? [o/N]"
    read confirm
    if [[ $confirm != "o" ]]; then
        echo "Annulation."
        exit 1
    fi
fi

# Variables de partitionnement pour Gentoo (sans toucher à la partition Windows)
EFI_SIZE="512MiB"
SWAP_SIZE="8GiB"
ROOT_SIZE="100%" # Utiliser tout l'espace restant pour la partition racine Gentoo

ROOT_PART="${DISK}1"
SWAP_PART="${DISK}2"
EFI_PART="${DISK}3" # Pour un système UEFI

# Confirmation du formatage des partitions pour Gentoo
echo "Les partitions suivantes seront créées pour Gentoo sur le disque $DISK :"
echo "- EFI : $EFI_SIZE"
echo "- SWAP : $SWAP_SIZE"
echo "- Root : Espace restant"
read -p "Voulez-vous continuer ? [o/N] " confirm
if [[ $confirm != "o" ]]; then
    echo "Annulation."
    exit 1
fi

# Mise à jour de l'horloge système
echo "Synchronisation de l'horloge système..."
timedatectl set-ntp true || { echo "Échec de la synchronisation de l'horloge"; exit 1; }

# Création des partitions pour Gentoo sans affecter les partitions Windows
echo "Création des partitions pour Gentoo..."
parted $DISK mkpart primary fat32 1MiB $EFI_SIZE || { echo "Erreur lors de la création de la partition EFI"; exit 1; }
parted $DISK mkpart primary linux-swap $EFI_SIZE $SWAP_SIZE || { echo "Erreur lors de la création de la partition swap"; exit 1; }
parted $DISK mkpart primary ext4 $SWAP_SIZE $ROOT_SIZE || { echo "Erreur lors de la création de la partition racine"; exit 1; }

# Formater les partitions
echo "Formatage des partitions..."
mkfs.fat -F32 $EFI_PART || { echo "Échec du formatage de la partition EFI"; exit 1; }
mkswap $SWAP_PART || { echo "Échec du formatage de la partition swap"; exit 1; }
swapon $SWAP_PART || { echo "Échec de l'activation du swap"; exit 1; }
mkfs.ext4 $ROOT_PART || { echo "Échec du formatage de la partition racine"; exit 1; }

# Monter la partition racine
echo "Montage de la partition racine..."
mount $ROOT_PART /mnt || { echo "Échec du montage de la partition racine"; exit 1; }

# Si UEFI, monter la partition EFI
if [ -b $EFI_PART ]; then
    mkdir -p /mnt/boot/efi
    mount $EFI_PART /mnt/boot/efi || { echo "Échec du montage de la partition EFI"; exit 1; }
fi

# Téléchargement et extraction du stage3
echo "Téléchargement et extraction du stage3..."
wget http://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-systemd.tar.xz -O /mnt/stage3.tar.xz || { echo "Échec du téléchargement de stage3"; exit 1; }
tar xpvf /mnt/stage3.tar.xz -C /mnt || { echo "Échec de l'extraction de stage3"; exit 1; }

# Préparation du chroot
echo "Préparation du chroot..."
mount --bind /dev /mnt/dev
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys
mount --bind /run /mnt/run

# Exécuter les commandes dans le chroot
echo "Chroot dans le système installé..."
chroot /mnt /bin/bash <<EOF

# Configuration du système
echo "Configuration de Portage et des locales..."
echo 'GRP=notfound' >> /etc/portage/make.conf
echo 'L10N="fr_FR.UTF-8"' >> /etc/portage/make.conf
echo 'USE="minimal X wayland networkmanager pulseaudio"' >> /etc/portage/make.conf

# Générer les locales
echo "fr_FR.UTF-8 UTF-8" > /etc/locale.gen
locale-gen

# Mise à jour de Portage
emerge-webrsync || { echo "Échec de la mise à jour de Portage"; exit 1; }
emerge --sync || { echo "Échec de la synchronisation des paquets"; exit 1; }

# Installer le noyau et les outils de base
emerge sys-kernel/gentoo-sources sys-kernel/genkernel || { echo "Échec de l'installation du noyau"; exit 1; }
genkernel all || { echo "Échec de la génération du noyau"; exit 1; }

# Installation de GRUB avec détection de Windows
emerge sys-boot/grub:2 || { echo "Échec de l'installation de GRUB"; exit 1; }

# Si UEFI, installation de GRUB dans la partition EFI
if [[ -d /sys/firmware/efi ]]; then
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Gentoo || { echo "Échec de l'installation de GRUB en mode UEFI"; exit 1; }
else
    grub-install $DISK || { echo "Échec de l'installation de GRUB en mode BIOS"; exit 1; }
fi

# Configurer GRUB pour détecter Windows
echo "Génération du fichier de configuration de GRUB..."
grub-mkconfig -o /boot/grub/grub.cfg || { echo "Échec de la génération du fichier de configuration de GRUB"; exit 1; }

# Création de l'utilisateur
read -p "Entrez le nom d'utilisateur à créer : " username
useradd -m -G users,wheel -s /bin/bash "$username" || { echo "Échec de la création de l'utilisateur"; exit 1; }
passwd $username || { echo "Échec de la définition du mot de passe"; exit 1; }

# Installer sudo
emerge app-admin/sudo || { echo "Échec de l'installation de sudo"; exit 1; }
echo "$username ALL=(ALL) ALL" >> /etc/sudoers

# Installer pipx, Ansible, et autres outils
emerge dev-python/pipx dev-python/ansible app-editors/nano app-editors/vim dev-vcs/git net-misc/curl || { echo "Échec de l'installation des outils"; exit 1; }

# Configurer fstab
echo "UUID=$(blkid -s UUID -o value $ROOT_PART) / ext4 defaults 0 1" >> /etc/fstab
echo "UUID=$(blkid -s UUID -o value $SWAP_PART) none swap sw 0 0" >> /etc/fstab
echo "UUID=$(blkid -s UUID -o value $EFI_PART) /boot/efi vfat defaults 0 2" >> /etc/fstab

EOF

# Démontage des partitions et redémarrage
echo "Démontage des partitions..."
umount -R /mnt/{dev,proc,sys,run}

echo "Redémarrage..."
reboot
