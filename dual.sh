#!/bin/bash

############################### Formatage + Création des partitions ###############################

# Nettoyage du disque si aucun système d'exploitation détecté
clean_disk() {
    echo "Aucun autre système détecté, nettoyage complet du disque."

    if [ ! -b "/dev/$DISK" ]; then
        echo "Le disque /dev/$DISK n'existe pas."
        exit 1
    fi

    # wipefs --force --all /dev/$DISK || { echo "Erreur lors du nettoyage du disque"; exit 1; }
    sgdisk --zap-all /dev/$DISK
}


# Détection automatique du disque principal (en excluant les périphériques amovibles)
echo "Détection du disque principal..."
DISK=$(lsblk -dno NAME,TYPE | awk '$2 == "disk" {print $1}' | head -n 1)  # Récupère uniquement le nom du disque
echo "Disque détecté : /dev/$DISK"

# Vérification de l'existence du disque
if [ -z "$DISK" ]; then
    echo "Aucun disque principal trouvé."
    exit 1
fi

# Nettoyage du disque si nécessaire
clean_disk

# Obtenir la taille du disque en bytes
DISK_SIZE=$(blockdev --getsize64 /dev/$DISK)

# Calculer la taille des partitions
EFI_SIZE=$((100 * 1024 * 1024))        # 100 MiB
LINUX_FS_SIZE=$((1 * 1024 * 1024 * 1024)) # 1 GiB
LVM_SIZE=$((DISK_SIZE - EFI_SIZE - LINUX_FS_SIZE)) # Reste du disque pour LVM

# Vérifier que le LVM est d'une taille positive
if [ $LVM_SIZE -le 0 ]; then
    echo "Erreur : Pas assez d'espace pour créer les partitions."
    exit 1
fi

# Convertir LVM_SIZE en secteurs (512 bytes par secteur)
LVM_SIZE_SECTORS=$((LVM_SIZE / 512))

# Création de la table de partition GPT
echo "Création de la table de partition GPT sur /dev/$DISK..."
parted /dev/$DISK --script mklabel gpt

# Création des partitions
echo "Création de la partition EFI..."
parted /dev/$DISK --script mkpart primary fat32 1MiB 100MiB
parted /dev/$DISK --script set 1 esp on

echo "Création de la partition Linux filesystem..."
parted /dev/$DISK --script mkpart primary ext4 100MiB 1100MiB

echo "Création de la partition Linux LVM..."
parted /dev/$DISK --script mkpart primary 8e00 1100MiB 100%

# Mise à jour des partitions
echo "Création des partitions terminée."

# # Formattage des partitions
# echo "Formatage de la partition EFI..."
# mkfs.fat -F32 /dev/${DISK}1

# echo "Formatage de la partition Linux filesystem..."
# mkfs.ext4 /dev/${DISK}2

# echo "Création du volume physique LVM..."
# pvcreate /dev/${DISK}3

# # Création d'un groupe de volumes
# echo "Création du groupe de volumes 'vg0'..."
# vgcreate vg0 /dev/${DISK}3

# # Création des volumes logiques
# echo "Création du volume logique 'rootlv' de 50 Go..."
# lvcreate -n rootlv -L 50G vg0

# echo "Création du volume logique 'swaplv' de 2 Go..."
# lvcreate -n swaplv -L 2G vg0

# echo "Création du volume logique 'homelv' pour le reste du disque..."
# lvcreate -n homelv -l +100%FREE vg0

# # Formatage des volumes logiques
# echo "Formatage du volume logique 'rootlv'..."
# mkfs.ext4 /dev/vg0/rootlv

# echo "Formatage du volume logique 'swaplv'..."
# mkswap /dev/vg0/swaplv

# echo "Création et formatage des partitions terminés."


############################### Montage des partitions et volumes logique ###############################


# # Montage du volume logique racine dans/mnt/gentoo
# mount /dev/vg0/rootlv /mnt/gentoo || { echo "Erreur lors du montage de la partition racine"; exit 1; }

# # Créé le dossier boot et on monte la partition boot
# mkdir -p /mnt/gentoo/boot || { echo "Erreur lors de la création du point de montage pour boot"; exit 1; }
# mount /dev/${DISK}2 /mnt/gentoo/boot || { echo "Erreur lors du montage de la partition boot"; exit 1; }

# # Dans le cas UEFI, monter aussi la partition FAT32 dans /boot/EFI
# mkdir -p /mnt/gentoo/boot/EFI || { echo "Erreur lors de la création du point de montage pour EFI"; exit 1; }
# mount /dev/${DISK}1 /mnt/gentoo/boot/EFI || { echo "Erreur lors du montage de la partition EFI"; exit 1; }

# # Créé les points de montage des autres volumes logiques et on monte ceux-ci dans leurs dossiers respectifs
# mkdir -p /mnt/gentoo/home || { echo "Erreur lors de la création du point de montage pour home"; exit 1; }
# mount /dev/vg0/homelv /mnt/gentoo/home || { echo "Erreur lors du montage de la partition home"; exit 1; }

# # On active le swap
# swapon /dev/vg0/swaplv || { echo "Erreur lors de l'activation de la partition swap"; exit 1; }


# ############################### Installation du systeme ###############################

# # Mise à jour de l'horloge système
# echo "Synchronisation de l'horloge système..."
# timedatectl set-ntp true || { echo "Échec de la synchronisation de l'horloge"; exit 1; }

# # Téléchargement et extraction de l'archive Gentoo
# echo "Téléchargement et extraction de Gentoo..."
# wget https://bouncer.gentoo.org/fetch/root/all/releases/amd64/autobuilds/latest-stage3-amd64-systemd.txt -O stage3-amd64.txt
# STAGE3_URL=$(grep -v '^#' stage3-amd64.txt | awk '{print $1}')
# wget https://bouncer.gentoo.org/fetch/root/all/releases/amd64/autobuilds/${STAGE3_URL} -O stage3-amd64.tar.xz
# tar xpvf stage3-amd64.tar.xz --xattrs-include='*.*' --numeric-owner -C /mnt/gentoo

# # Monter les partitions nécessaires
# echo "Montage des partitions pour l'installation..."
# mount --types proc /proc /mnt/gentoo/proc || { echo "Erreur lors du montage de /proc"; exit 1; }
# mount --rbind /sys /mnt/gentoo/sys || { echo "Erreur lors du montage de /sys"; exit 1; }
# mount --make-rslave /mnt/gentoo/sys || { echo "Erreur lors de la mise à jour de /sys"; exit 1; }
# mount --rbind /dev /mnt/gentoo/dev || { echo "Erreur lors du montage de /dev"; exit 1; }
# mount --make-rslave /mnt/gentoo/dev || { echo "Erreur lors de la mise à jour de /dev"; exit 1; }

# # Copie de la configuration réseau pour qu'elle soit disponible dans le chroot
# cp /etc/resolv.conf /mnt/gentoo/etc/

# # Entrée dans l'environnement chroot
# echo "Entrée dans l'environnement chroot..."
# chroot /mnt/gentoo /bin/bash << "EOL"

# # Mise à jour des variables d'environnement
# source /etc/profile
# export PS1="(chroot) ${PS1}"

# # Monter le boot
# mkdir -p /boot/efi

# # Configurer le fuseau horaire
# echo "Europe/Paris" > /etc/timezone
# emerge --config sys-libs/timezone-data

# # Configuration des locales
# echo "fr_FR.UTF-8 UTF-8" >> /etc/locale.gen
# locale-gen
# eselect locale set fr_FR.utf8
# env-update && source /etc/profile

# # Mettre à jour l'environnement
# env-update && source /etc/profile

# # Synchroniser le système Portage
# echo "Synchronisation du dépôt Portage..."
# emerge --sync

# # Mise à jour du profil
# eselect profile list
# eselect profile set 1  # Choix du profil par défaut (par exemple, profil desktop)

# # Mise à jour du système de base (optionnel)
# emerge --ask --verbose --update --deep --newuse @world

# # Installation du noyau Linux
# echo "Installation du noyau Linux..."
# emerge --ask sys-kernel/gentoo-sources

# # Configuration du noyau
# cd /usr/src/linux
# make menuconfig  # Configuration du noyau à la main

# # Compilation et installation du noyau
# make && make modules_install
# make install

# # Installation des outils de base
# emerge --ask sys-apps/util-linux sys-apps/net-tools

# # Installation de GRUB
# emerge --ask sys-boot/grub

# # Configuration de GRUB
# grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Gentoo
# grub-mkconfig -o /boot/grub/grub.cfg

# # Sortir de l'environnement chroot
# exit
# EOL

# # Démontage des partitions
# echo "Démontage des partitions..."
# umount -R /mnt/gentoo || { echo "Erreur lors du démontage des partitions"; exit 1; }

# echo "Installation terminée. Vous pouvez maintenant redémarrer votre système."
