#!/bin/bash

# Détection automatique du dual boot (Windows ou autre OS)
detect_dual_boot() {
    echo "Vérification de la présence d'un autre système d'exploitation (Windows ou autre Linux)..."
    if os-prober | grep -q "Windows"; then
        echo "Windows détecté sur le disque."
        DUAL_BOOT="yes"
    elif os-prober | grep -q "Linux"; then
        echo "Un autre système Linux est détecté."
        DUAL_BOOT="yes"
    else
        echo "Aucun autre système d'exploitation détecté."
        DUAL_BOOT="no"
    fi
}

# Nettoyage du disque si aucun système d'exploitation détecté
clean_disk_if_needed() {
    if [[ $DUAL_BOOT == "no" ]]; then
        echo "Aucun autre système détecté, nettoyage complet du disque."
        wipefs -a $DISK || { echo "Erreur lors du nettoyage du disque"; exit 1; }
    fi
}

# Afficher les disques disponibles (en excluant les loop devices et disques externes)
echo "Disques disponibles :"
lsblk -nd --output NAME,SIZE,TYPE | grep "disk"

# Demander à l'utilisateur de choisir un disque pour l'installation
read -p "Entrez le nom du disque sur lequel installer Gentoo (ex : sda) : " DISK
DISK="/dev/$DISK"

# Détection du dual boot avant de commencer le partitionnement
detect_dual_boot

# Confirmation avant de nettoyer le disque sélectionné
echo "Vous avez sélectionné le disque : $DISK"
read -p "Voulez-vous continuer et effacer le disque $DISK ? [o/N] " confirm
if [[ $confirm != "o" ]]; then
    echo "Annulation de l'opération."
    exit 1
fi

# Nettoyage du disque si nécessaire (si pas de dual boot)
clean_disk_if_needed

# Création d'une nouvelle table de partitions GPT
echo "Création d'une nouvelle table de partitions GPT sur $DISK..."
parted $DISK mklabel gpt || { echo "Erreur lors de la création du label GPT"; exit 1; }

# Demander à l'utilisateur de définir les tailles des partitions
read -p "Entrez la taille de la partition EFI (ex : 512MiB) : " EFI_SIZE  # Partition EFI pour le bootloader.
read -p "Entrez la taille de la partition swap (ex : 8GiB) : " SWAP_SIZE  # Partition swap pour la RAM virtuelle.

# Demander à l'utilisateur s'il souhaite spécifier la taille de la partition racine ou utiliser tout l'espace restant
read -p "Souhaitez-vous spécifier la taille de la partition racine ? (o/n) : " specify_root_size

if [[ $specify_root_size == "o" ]]; then
    # Si l'utilisateur souhaite spécifier la taille de la partition racine
    read -p "Entrez la taille de la partition racine (ex : 40GiB) : " ROOT_SIZE  # Taille personnalisée pour la partition racine.
else
    # Utiliser tout l'espace disque restant pour la partition racine
    echo "La partition racine utilisera tout l'espace disque restant après la création des autres partitions."
    ROOT_SIZE="100%"
fi

# Partitionnement du disque
echo "Partitionnement du disque $DISK..."
parted $DISK mkpart primary fat32 1MiB ${EFI_SIZE} || { echo "Erreur lors de la création de la partition EFI"; exit 1; }
parted $DISK mkpart primary ${EFI_SIZE} $((${EFI_SIZE%%MiB} + ${SWAP_SIZE%%GiB} * 1024))MiB || { echo "Erreur lors de la création de la partition LVM"; exit 1; }

# Activer LVM sur la deuxième partition
pvcreate ${DISK}2 || { echo "Erreur lors de la création du volume physique LVM"; exit 1; }
vgcreate vg_gentoo ${DISK}2 || { echo "Erreur lors de la création du groupe de volumes LVM"; exit 1; }

# Création des volumes logiques pour le swap et la racine
lvcreate -L ${SWAP_SIZE} -n swap vg_gentoo || { echo "Erreur lors de la création du volume logique swap"; exit 1; }
if [[ $specify_root_size == "o" ]]; then
    lvcreate -L ${ROOT_SIZE} -n root vg_gentoo || { echo "Erreur lors de la création du volume logique root"; exit 1; }
else
    lvcreate -l 100%FREE -n root vg_gentoo || { echo "Erreur lors de l'utilisation de tout l'espace disque pour la partition racine"; exit 1; }
fi

# Formater les partitions
EFI_PART="${DISK}1"      # Partition EFI pour le bootloader
SWAP_PART="/dev/vg_gentoo/swap"  # Volume logique pour la partition swap
ROOT_PART="/dev/vg_gentoo/root"  # Volume logique pour la partition racine

echo "Formatage des partitions..."
mkfs.fat -F32 $EFI_PART || { echo "Échec du formatage de la partition EFI"; exit 1; }  # Formatage en FAT32 pour la partition EFI
mkswap $SWAP_PART || { echo "Échec du formatage de la partition swap"; exit 1; }  # Formatage en swap pour le volume swap
swapon $SWAP_PART || { echo "Échec de l'activation du swap"; exit 1; }  # Activation de la partition swap
mkfs.ext4 $ROOT_PART || { echo "Échec du formatage de la partition racine"; exit 1; }  # Formatage en ext4 pour la partition racine

# Mise à jour de l'horloge système
echo "Synchronisation de l'horloge système..."
timedatectl set-ntp true || { echo "Échec de la synchronisation de l'horloge"; exit 1; }

# Monter les partitions pour l'installation de Gentoo
echo "Montage des partitions..."
mount $ROOT_PART /mnt/gentoo || { echo "Erreur lors du montage de la partition racine"; exit 1; }
mkdir -p /mnt/gentoo/boot/efi || { echo "Erreur lors de la création du point de montage EFI"; exit 1; }
mount $EFI_PART /mnt/gentoo/boot/efi || { echo "Erreur lors du montage de la partition EFI"; exit 1; }

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
cat <<EOF > /etc/fstab
/dev/mapper/vg_gentoo-root / ext4 defaults 0 1
/dev/mapper/vg_gentoo-swap none swap sw 0 0
/dev/sda1 /boot/efi vfat defaults 0 2
EOF

# Configuration du réseau
echo "hostname=\"gentoo\"" > /etc/conf.d/hostname

# Configurer le fichier réseau pour DHCP (par exemple)
cat <<EOF > /etc/conf.d/net
config_eth0="dhcp"
EOF
ln -s /etc/init.d/net.lo /etc/init.d/net.eth0
rc-update add net.eth0 default

# Installer le système de gestion des fichiers système
emerge sys-fs/lvm2
rc-update add lvm boot

# Installer GRUB avec support LVM et EFI
echo "Installation de GRUB pour gérer le dual boot..."
emerge sys-boot/grub:2
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=gentoo --recheck
grub-mkconfig -o /boot/grub/grub.cfg

# Sortir de l'environnement chroot
exit
EOL

# Finalisation de l'installation
echo "Finalisation de l'installation Gentoo..."
umount -l /mnt/gentoo/dev{/shm,/pts,}
umount -R /mnt/gentoo/sys
umount -R /mnt/gentoo/proc
umount /mnt/gentoo/boot/efi
umount /mnt/gentoo

echo "Installation terminée. Vous pouvez redémarrer votre machine."

# Redémarrer le système
read -p "Voulez-vous redémarrer maintenant ? (o/n) : " reboot_choice
if [[ $reboot_choice == "o" ]]; then
    reboot
fi

