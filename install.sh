#!/bin/bash

# Vérifier si le script est exécuté avec des privilèges root
if [[ $EUID -ne 0 ]]; then
   echo "Ce script doit être exécuté en tant que root." 
   exit 1
fi

# Détection automatique du disque principal (en excluant les périphériques amovibles)
DISK=$(lsblk -nd --output NAME,SIZE,TYPE | grep "disk" | sort -k2 -h | tail -n 1 | awk '{print "/dev/" $1}')
echo "Disque détecté : $DISK"

# Variables de partitionnement
ROOT_PART="${DISK}1"
SWAP_PART="${DISK}2"
EFI_PART="${DISK}3" # Pour un système UEFI

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
parted $DISK mklabel gpt || { echo "Erreur lors de la création du label GPT"; exit 1; }
parted $DISK mkpart primary fat32 1MiB 512MiB || { echo "Erreur lors de la création de la partition EFI"; exit 1; }
parted $DISK mkpart primary linux-swap 512MiB 8GiB || { echo "Erreur lors de la création de la partition swap"; exit 1; }
parted $DISK mkpart primary ext4 8GiB 100% || { echo "Erreur lors de la création de la partition racine"; exit 1; }

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

# Installation du système de base
echo "Téléchargement et extraction du stage3..."
wget http://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64.tar.xz -O /mnt/stage3.tar.xz || { echo "Échec du téléchargement de stage3"; exit 1; }
tar xpvf /mnt/stage3.tar.xz --xattrs-include='*.*' -C /mnt || { echo "Échec de l'extraction de stage3"; exit 1; }

# Chroot dans le système installé
echo "Préparation du chroot..."
mount --bind /dev /mnt/dev
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys

# Exécuter les commandes dans le chroot
echo "Chroot dans le système installé..."
chroot /mnt /bin/bash <<EOF

# Configuration du système
echo "Configuration de Portage et des locales..."
echo "GRP=notfound" >> /etc/portage/make.conf
echo "L10N=\"fr_FR.UTF-8\"" >> /etc/portage/make.conf
echo "USE=\"minimal X wayland networkmanager pulseaudio\"" >> /etc/portage/make.conf

# Générer les locales
echo "fr_FR.UTF-8 UTF-8" > /etc/locale.gen
locale-gen

# Mise à jour de Portage
emerge-webrsync || { echo "Échec de la mise à jour de Portage"; exit 1; }

# Installer le noyau et les outils de base
emerge sys-kernel/gentoo-sources sys-kernel/genkernel || { echo "Échec de l'installation du noyau"; exit 1; }
genkernel all || { echo "Échec de la génération du noyau"; exit 1; }

# Installation des pilotes vidéo en fonction du matériel détecté
if lspci | grep -i vga | grep -i nvidia; then
    emerge x11-drivers/nvidia-drivers || { echo "Échec de l'installation des pilotes NVIDIA"; exit 1; }
elif lspci | grep -i vga | grep -i intel; then
    emerge x11-drivers/xf86-video-intel || { echo "Échec de l'installation des pilotes Intel"; exit 1; }
elif lspci | grep -i vga | grep -i amd; then
    emerge x11-drivers/xf86-video-amdgpu || { echo "Échec de l'installation des pilotes AMD"; exit 1; }
else
    emerge x11-drivers/xf86-video-vesa || { echo "Échec de l'installation des pilotes par défaut"; exit 1; }
fi

# Installation de Hyprland et des dépendances
eselect repository enable guru
emaint sync -r guru
emerge gui-wm/hyprland gui-apps/hyprlock gui-apps/hypridle gui-libs/xdg-desktop-portal-hyprland gui-apps/hyprland-plugins gui-apps/hyprpaper gui-apps/hyprpicker || { echo "Échec de l'installation de Hyprland"; exit 1; }

# Installer NetworkManager pour la gestion réseau
emerge net-misc/networkmanager || { echo "Échec de l'installation de NetworkManager"; exit 1; }
systemctl enable NetworkManager

# Installer PulseAudio pour le son
emerge media-sound/pulseaudio || { echo "Échec de l'installation de PulseAudio"; exit 1; }

# Créer un utilisateur
useradd -m -G users,wheel -s /bin/bash alexandre || { echo "Échec de la création de l'utilisateur"; exit 1; }
echo "alexandre:password" | chpasswd

# Installer sudo et configurer pour l'utilisateur
emerge app-admin/sudo || { echo "Échec de l'installation de sudo"; exit 1; }
echo "alexandre ALL=(ALL) ALL" >> /etc/sudoers

# Installer pipx, Ansible, et autres outils
emerge dev-python/pipx dev-python/ansible app-editors/nano app-editors/vim dev-vcs/git net-misc/curl || { echo "Échec de l'installation des outils"; exit 1; }

# Configurer le fichier fstab
echo "UUID=$(blkid -s UUID -o value $ROOT_PART) / ext4 defaults 0 1" >> /etc/fstab
echo "UUID=$(blkid -s UUID -o value $SWAP_PART) none swap sw 0 0" >> /etc/fstab
echo "UUID=$(blkid -s UUID -o value $EFI_PART) /boot/efi vfat defaults 0 2" >> /etc/fstab

EOF

# Démontage et redémarrage
echo "Démontage des partitions et redémarrage..."
umount -R /mnt
reboot
