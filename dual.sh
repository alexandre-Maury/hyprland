#!/bin/bash

# Nettoyage du disque si aucun système d'exploitation détecté
clean_disk_if_needed() {
    echo "Aucun autre système détecté, nettoyage complet du disque."
    if [ ! -b "/dev/$DISK" ]; then
        echo "Le disque /dev/$DISK n'existe pas."
        exit 1
    fi

    wipefs -a /dev/$DISK || { echo "Erreur lors du nettoyage du disque"; exit 1; }
}

# Détection automatique du disque principal (en excluant les périphériques amovibles)
echo "Détection du disque principal..."
DISK=$(lsblk -dno NAME,TYPE | grep disk | grep -v "loop" | head -n 1)
echo "Disque détecté : /dev/$DISK"  # Vérifiez la valeur ici
if [ -z "$DISK" ]; then
    echo "Aucun disque principal trouvé."
    exit 1
fi

# Nettoyage du disque si nécessaire
clean_disk_if_needed

# Demander à l'utilisateur de définir les tailles des partitions
read -p "Entrez la taille de la partition EFI (ex : 100MiB) : " EFI_SIZE  # La partition EFI contient les fichiers nécessaires au démarrage du système.
read -p "Entrez la taille de la partition boot (ex : 1GiB) : " BOOT_SIZE  # La partition boot est utilisée pour stocker les fichiers de démarrage.
read -p "Souhaitez-vous spécifier la taille de la partition racine ? (o/n) : " specify_root_size

if [[ $specify_root_size == "o" ]]; then
    read -p "Entrez la taille de la partition racine (ex : 50GiB) : " ROOT_SIZE  # L'utilisateur spécifie la taille de la partition racine.
else
    echo "La partition racine utilisera tout l'espace disque restant après la création des autres partitions."
    ROOT_SIZE="100%"  # Utiliser tout l'espace disque restant pour la partition racine.
fi

# Confirmation du formatage du disque détecté
read -p "Le disque $DISK sera formaté. Voulez-vous continuer ? [o/N] " confirm
if [[ $confirm != "o" ]]; then
    echo "Annulation du formatage."
    exit 1
fi

# Mise à jour de l'horloge système
echo "Synchronisation de l'horloge système..."
timedatectl set-ntp true || { echo "Échec de la synchronisation de l'horloge"; exit 1; }

# Partitionnement du disque
echo "Partitionnement du disque $DISK..."
parted /dev/$DISK mklabel gpt || { echo "Erreur lors de la création du label GPT"; exit 1; }
parted /dev/$DISK mkpart primary fat32 1MiB ${EFI_SIZE} || { echo "Erreur lors de la création de la partition EFI"; exit 1; }
parted /dev/$DISK mkpart primary ext4 ${EFI_SIZE} ${BOOT_SIZE} || { echo "Erreur lors de la création de la partition boot"; exit 1; }
parted /dev/$DISK mkpart primary lvm ${BOOT_SIZE} 100% || { echo "Erreur lors de la création de la partition LVM"; exit 1; }

# Formater les partitions
EFI_PART="/dev/${DISK}1"
BOOT_PART="/dev/${DISK}2"
LVM_PART="/dev/${DISK}3"

echo "Formatage des partitions..."
mkfs.fat -F32 $EFI_PART || { echo "Échec du formatage de la partition EFI"; exit 1; }
mkfs.ext4 $BOOT_PART || { echo "Échec du formatage de la partition boot"; exit 1; }

# Création de la partie LVM
pvcreate $LVM_PART || { echo "Erreur lors de la création du volume physique LVM"; exit 1; }
vgcreate rootvg $LVM_PART || { echo "Erreur lors de la création du groupe de volumes LVM"; exit 1; }
lvcreate -n rootlv -L $ROOT_SIZE rootvg || { echo "Erreur lors de la création du volume logique racine"; exit 1; }
lvcreate -n swaplv -L 2G rootvg || { echo "Erreur lors de la création du volume logique swap"; exit 1; }
lvcreate -n homelv -l +100%FREE rootvg || { echo "Erreur lors de la création du volume logique home"; exit 1; }

# Formater les volumes logiques
mkfs.ext4 /dev/rootvg/rootlv || { echo "Erreur lors du formatage de la partition racine"; exit 1; }
mkfs.ext4 /dev/rootvg/homelv || { echo "Erreur lors du formatage de la partition home"; exit 1; }
mkswap /dev/rootvg/swaplv || { echo "Erreur lors de la création de la partition swap"; exit 1; }

# Montage des partitions
mount /dev/rootvg/rootlv /mnt/gentoo || { echo "Erreur lors du montage de la partition racine"; exit 1; }
mkdir -p /mnt/gentoo/boot || { echo "Erreur lors de la création du point de montage pour boot"; exit 1; }
mount $BOOT_PART /mnt/gentoo/boot || { echo "Erreur lors du montage de la partition boot"; exit 1; }
mkdir -p /mnt/gentoo/boot/EFI || { echo "Erreur lors de la création du point de montage pour EFI"; exit 1; }
mount $EFI_PART /mnt/gentoo/boot/EFI || { echo "Erreur lors du montage de la partition EFI"; exit 1; }
mkdir -p /mnt/gentoo/home || { echo "Erreur lors de la création du point de montage pour home"; exit 1; }
mount /dev/rootvg/homelv /mnt/gentoo/home || { echo "Erreur lors du montage de la partition home"; exit 1; }
swapon /dev/rootvg/swaplv || { echo "Erreur lors de l'activation de la partition swap"; exit 1; }

# Téléchargement et extraction de l'archive Gentoo
echo "Téléchargement et extraction de Gentoo..."
wget https://bouncer.gentoo.org/fetch/root/all/releases/amd64/autobuilds/latest-stage3-amd64-systemd.txt -O stage3-amd64.txt
STAGE3_URL=$(grep -v '^#' stage3-amd64.txt | awk '{print $1}')
wget https://bouncer.gentoo.org/fetch/root/all/releases/amd64/autobuilds/${STAGE3_URL} -O stage3-amd64.tar.xz
tar xpvf stage3-amd64.tar.xz --xattrs-include='*.*' --numeric-owner -C /mnt/gentoo

# Monter les partitions nécessaires
echo "Montage des partitions pour l'installation..."
mount --types proc /proc /mnt/gentoo/proc || { echo "Erreur lors du montage de /proc"; exit 1; }
mount --rbind /sys /mnt/gentoo/sys || { echo "Erreur lors du montage de /sys"; exit 1; }
mount --make-rslave /mnt/gentoo/sys || { echo "Erreur lors de la mise à jour de /sys"; exit 1; }
mount --rbind /dev /mnt/gentoo/dev || { echo "Erreur lors du montage de /dev"; exit 1; }
mount --make-rslave /mnt/gentoo/dev || { echo "Erreur lors de la mise à jour de /dev"; exit 1; }

# Copie de la configuration réseau pour qu'elle soit disponible dans le chroot
cp /etc/resolv.conf /mnt/gentoo/etc/

# Entrée dans l'environnement chroot
echo "Entrée dans l'environnement chroot..."
chroot /mnt/gentoo /bin/bash << "EOL"

# Mise à jour des variables d'environnement
source /etc/profile
export PS1="(chroot) ${PS1}"

# Monter le boot
mkdir -p /boot/efi

# Configurer le fuseau horaire
echo "Europe/Paris" > /etc/timezone
emerge --config sys-libs/timezone-data

# Configuration des locales
echo "fr_FR.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
eselect locale set fr_FR.utf8
env-update && source /etc/profile

# Mettre à jour l'environnement
env-update && source /etc/profile

# Synchroniser le système Portage
echo "Synchronisation du dépôt Portage..."
emerge --sync

# Mise à jour du profil
eselect profile list
eselect profile set 1  # Choix du profil par défaut (par exemple, profil desktop)

# Mise à jour du système de base (optionnel)
emerge --ask --verbose --update --deep --newuse @world

# Installation du noyau Linux
echo "Installation du noyau Linux..."
emerge sys-kernel/gentoo-sources
cd /usr/src/linux
make menuconfig  # Configurer le noyau selon tes besoins ou utiliser une configuration par défaut

# Compilation et installation du noyau
make -j$(nproc)
make modules_install
make install

# Installation d'initramfs pour LVM
emerge sys-kernel/genkernel
genkernel --lvm initramfs

# Configuration du fichier fstab
echo "Création du fichier fstab..."
cat <<EOF >> /etc/fstab
/dev/mapper/rootvg-rootlv /               ext4    noatime         0 1
/dev/mapper/rootvg-homelv /home           ext4    noatime         0 2
/dev/mapper/rootvg-swaplv none            swap    sw              0 0
EOF

# Sortie de l'environnement chroot
EOL

# Nettoyage des montages
echo "Nettoyage des montages..."
umount -R /mnt/gentoo/dev
umount -R /mnt/gentoo/sys
umount -R /mnt/gentoo/proc
umount -R /mnt/gentoo/boot/EFI
umount -R /mnt/gentoo/boot
umount -R /mnt/gentoo/home
umount -R /mnt/gentoo

echo "Installation de Gentoo terminée !"
