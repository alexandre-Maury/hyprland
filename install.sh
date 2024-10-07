#!/bin/bash

# Variables
# DISK="/dev/sda"
BOOT_SIZE="128M"  # Taille de la partition /boot
LVM_SIZE="remaining"  # Taille de la partition LVM (tout l'espace restant)
SWAP_SIZE="2G"  # Taille du swap
ROOT_SIZE="50G"  # Taille du volume logique root
HOSTNAME="gentoo-system"  # Nom du système

# Vérification des droits superutilisateur
if [ "$EUID" -ne 0 ]; then
  echo "Ce script doit être exécuté en tant que root."
  exit 1
fi

# Détection automatique du disque principal (en excluant les périphériques amovibles)
echo "=== Détection du disque principal ==="
DISK=$(lsblk -dno NAME,TYPE | awk '$2 == "disk" {print $1}' | head -n 1)  # Récupère uniquement le nom du disque
echo "Disque détecté : /dev/$DISK"

# Nettoyage du disque si nécessaire
echo "=== Nettoyage du disque ==="
# wipefs --force --all /dev/$DISK || { echo "Erreur lors du nettoyage du disque"; exit 1; }
sgdisk --zap-all /dev/$DISK

# ---------------------------------------------------
# PARTITIONNEMENT
# ---------------------------------------------------
echo "=== Partitionnement du disque $DISK ==="
parted -a optimal "$DISK" <<EOF
mklabel gpt
unit mib
mkpart primary 1 3
name 1 grub
set 1 bios_grub on
mkpart primary 3 131
name 2 boot
set 2 boot on
mkpart primary 131 -1
name 3 lvm
quit
EOF

# ---------------------------------------------------
# CHIFFREMENT LUKS
# ---------------------------------------------------
echo "=== Chiffrement de la partition LVM (/dev/sda3) ==="
modprobe dm-crypt  # Charger le module dm-crypt, si ce n'est pas déjà fait
cryptsetup -c aes-cbc-essiv:sha256 -v luksFormat -s 256 "${DISK}3"
cryptsetup luksOpen "${DISK}3" lvmcrypt

# ---------------------------------------------------
# CONFIGURATION LVM
# ---------------------------------------------------
echo "=== Configuration de LVM sur le disque chiffré ==="
# Initialiser LVM sur le volume chiffré
pvcreate /dev/mapper/lvmcrypt
vgcreate vg0 /dev/mapper/lvmcrypt

# Créer les volumes logiques
lvcreate -L "$SWAP_SIZE" -n swap vg0
lvcreate -L "$ROOT_SIZE" -n root vg0
lvcreate -l 100%FREE -n home vg0

# Formater les partitions
echo "=== Formatage des partitions ==="
mkfs.ext2 "${DISK}2"  # /boot
mkfs.ext4 /dev/vg0/root  # /
mkfs.ext4 /dev/vg0/home  # /home
mkswap /dev/vg0/swap  # swap
swapon /dev/vg0/swap

# ---------------------------------------------------
# INSTALLATION GENTOO
# ---------------------------------------------------
# echo "=== Installation de Gentoo ==="
# # Monter les systèmes de fichiers
# mount /dev/vg0/root /mnt/gentoo
# mkdir /mnt/gentoo/boot
# mount "${DISK}2" /mnt/gentoo/boot
# mkdir /mnt/gentoo/home
# mount /dev/vg0/home /mnt/gentoo/home

# # Télécharger et extraire le stage 3
# cd /mnt/gentoo
# STAGE3_URL=$(curl -s https://www.gentoo.org/downloads/mirrors/ | grep -m1 "autobuilds/current-stage3" | awk -F'"' '{print $2}')
# wget "$STAGE3_URL"
# tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner

# # Configurer make.conf
# echo "CFLAGS=\"-O2 -pipe\"" >> /mnt/gentoo/etc/portage/make.conf
# echo "CXXFLAGS=\"\${CFLAGS}\"" >> /mnt/gentoo/etc/portage/make.conf
# echo "MAKEOPTS=\"-j$(nproc)\"" >> /mnt/gentoo/etc/portage/make.conf

# # Monter les pseudo-filesystems
# mount -t proc /proc /mnt/gentoo/proc
# mount --rbind /sys /mnt/gentoo/sys
# mount --make-rslave /mnt/gentoo/sys
# mount --rbind /dev /mnt/gentoo/dev
# mount --make-rslave /mnt/gentoo/dev

# # Copier les informations de résolution DNS
# cp /etc/resolv.conf /mnt/gentoo/etc/

# # Chroot dans l'environnement Gentoo
# chroot /mnt/gentoo /bin/bash <<'EOF'
# source /etc/profile
# export PS1="(chroot) $PS1"

# # Mettre à jour l'environnement
# emerge-webrsync
# emerge --sync

# # Configurer le système de fichiers
# echo "LABEL=boot /boot ext2 defaults 0 2" >> /etc/fstab
# echo "/dev/vg0/root / ext4 defaults 0 1" >> /etc/fstab
# echo "/dev/vg0/home /home ext4 defaults 0 2" >> /etc/fstab
# echo "/dev/vg0/swap none swap sw 0 0" >> /etc/fstab

# # Configurer le réseau et le hostname
# echo "$HOSTNAME" > /etc/conf.d/hostname
# echo "127.0.0.1 $HOSTNAME localhost" >> /etc/hosts

# # Configurer les locales (exemple : fr_FR.UTF-8)
# echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
# locale-gen
# eselect locale set en_US.UTF-8
# env-update && source /etc/profile

# # Configurer le fuseau horaire
# echo "Europe/Paris" > /etc/timezone
# emerge --config sys-libs/timezone-data

# # Installer les outils de base
# emerge sys-kernel/gentoo-sources sys-kernel/genkernel sys-fs/lvm2 sys-apps/util-linux sys-boot/grub sys-fs/cryptsetup

# # Compilation du noyau avec le support LUKS et LVM
# genkernel --luks --lvm --busybox --menuconfig all

# # Installer GRUB
# grub-install "$DISK"
# echo "GRUB_CMDLINE_LINUX=\"crypt_root=UUID=$(blkid -s UUID -o value ${DISK}3) dolvm\"" >> /etc/default/grub
# grub-mkconfig -o /boot/grub/grub.cfg

# # Finaliser l'installation
# passwd  # Définir un mot de passe pour root
# EOF

# # Démonter les systèmes de fichiers
# umount -l /mnt/gentoo/dev{/shm,/pts,}
# umount -R /mnt/gentoo
# swapoff /dev/vg0/swap

# echo "Installation terminée ! Vous pouvez redémarrer."
