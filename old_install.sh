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
parted -a optimal "/dev/$DISK" <<EOF
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
cryptsetup -c aes-cbc-essiv:sha256 -v luksFormat -s 256 "/dev/${DISK}3"
cryptsetup luksOpen "/dev/${DISK}3" lvmcrypt

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
mkfs.ext2 "/dev/${DISK}2"  # /boot
mkfs.ext4 /dev/vg0/root  # /
mkfs.ext4 /dev/vg0/home  # /home
mkswap /dev/vg0/swap  # swap
swapon /dev/vg0/swap

# ---------------------------------------------------
# INSTALLATION GENTOO
# ---------------------------------------------------
echo "=== Installation de Gentoo ==="
# Monter les systèmes de fichiers
mkdir -p /mnt/gentoo
mount /dev/vg0/root /mnt/gentoo
mkdir -p /mnt/gentoo/boot
mount "/dev/${DISK}2" /mnt/gentoo/boot
mkdir -p /mnt/gentoo/home
mount /dev/vg0/home /mnt/gentoo/home

# 
echo "=== Télécharger et extraire le stage 3 ==="
cd /mnt/gentoo
wget https://distfiles.gentoo.org/releases/amd64/autobuilds/20240929T163611Z/stage3-amd64-systemd-20240929T163611Z.tar.xz -O stage3-amd64.tar.xz
tar xpvf stage3-amd64.tar.xz --xattrs-include='*.*' --numeric-owner || { echo "Échec de l'extraction de stage3"; exit 1; }

echo "=== Configurer make.conf avec les options d'optimisation personnalisées ==="
echo 'COMMON_FLAGS="-O2 -pipe -march=native"' >> /mnt/gentoo/etc/portage/make.conf
echo 'CFLAGS="${COMMON_FLAGS}"' >> /mnt/gentoo/etc/portage/make.conf
echo 'CXXFLAGS="${COMMON_FLAGS}"' >> /mnt/gentoo/etc/portage/make.conf
echo 'MAKEOPTS=\"-j$(nproc)\"' >> /mnt/gentoo/etc/portage/make.conf
echo 'L10N="fr_FR.UTF-8"' >> /mnt/gentoo/etc/portage/make.conf
echo 'VIDEO_CARDS="fbdev vesa intel i915 nvidia nouveau radeon amdgpu radeonsi virtualbox vmware qxl"' >> /mnt/gentoo/etc/portage/make.conf
echo 'INPUT_DEVICES="libinput synaptics keyboard mouse joystick wacom"' >> /mnt/gentoo/etc/portage/make.conf
echo 'EMERGE_DEFAULT_OPTS="${EMERGE_DEFAULT_OPTS} --quiet-build=y"' >> /mnt/gentoo/etc/portage/make.conf
echo 'PORTAGE_SCHEDULING_POLICY="idle"' >> /mnt/gentoo/etc/portage/make.conf
echo 'USE="lvm"' >> /mnt/gentoo/etc/portage/make.conf
echo 'ACCEPT_KEYWORDS="amd64"' >> /mnt/gentoo/etc/portage/make.conf
echo 'SYNC="rsync://rsync.gentoo.org/gentoo-portage"' >> /mnt/gentoo/etc/portage/make.conf
echo 'FEATURES="buildpkg"' >> /mnt/gentoo/etc/portage/make.conf
echo 'PORTAGE_NICENESS=19' >> /mnt/gentoo/etc/portage/make.conf
echo 'PORTAGE_TMPDIR="/var/tmp"' >> /mnt/gentoo/etc/portage/make.conf
echo 'GENTOO_MIRRORS="https://mirror.init7.net/gentoo/ http://ftp.snt.utwente.nl/pub/os/linux/gentoo/ http://mirror.leaseweb.com/gentoo/"' >> /mnt/gentoo/etc/portage/make.conf
echo 'DISTDIR="/var/cache/distfiles"' >> /mnt/gentoo/etc/portage/make.conf
echo 'PKGDIR="/var/cache/binpkgs"' >> /mnt/gentoo/etc/portage/make.conf
echo 'CHOST="x86_64-pc-linux-gnu"' >> /mnt/gentoo/etc/portage/make.conf

echo "=== Copier les informations de résolution DNS ==="
cp -L /etc/resolv.conf /mnt/gentoo/etc/

echo "=== Monter les pseudo-filesystems ==="
mount -t proc /proc /mnt/gentoo/proc
mount --rbind /dev /mnt/gentoo/dev
mount --rbind /sys /mnt/gentoo/sys

echo "=== Chroot dans l'environnement Gentoo ==="
chroot /mnt/gentoo /bin/bash <<EOF
env-update && source /etc/profile
export PS1="[chroot] $PS1"

echo "=== Mettre à jour l'environnement ==="
emerge-webrsync || { echo "Échec de la mise à jour de Portage"; exit 1; }
emerge --sync || { echo "Échec de la synchronisation des paquets"; exit 1; }

echo "=== Autorise tout dans le fichier package.licence ==="
mkdir -p /etc/portage/package.license
echo "*/* *" >> /etc/portage/package.license/custom
echo "sys-kernel/linux-firmware linux-fw-redistributable no-source-code" >> /etc/portage/package.license/custom 

echo "=== Paramétrer les dépôts binaires ==="
mkdir -p /etc/portage/binrepos.conf
echo '[binhost]' >> /etc/portage/binrepos.conf/gentoobinhost.conf
echo 'priority = 9999' >> /etc/portage/binrepos.conf/gentoobinhost.conf
echo 'sync-uri = https://distfiles.gentoo.org/releases/amd64/binpackages/23.0/x86-64-v3/' >> /etc/portage/binrepos.conf/gentoobinhost.conf

echo "=== Mise à jour du world ==="
emerge -avuDN @world

echo "=== Configuration de /etc/fstab ==="
# echo "/dev/sda2               /boot           ext4            defaults,noatime        0 2" >> /etc/fstab
# echo "/dev/sda1               /boot/EFI       vfat            defaults                0 0" >> /etc/fstab
# echo "/dev/vg0/root           /               ext4            defaults,noatime        0 1" >> /etc/fstab
# echo "/dev/vg0/home           /home           ext4            defaults,noatime        0 2" >> /etc/fstab
# echo "/dev/vg0/swap           none            swap            sw                      0 0" >> /etc/fstab



EFI_UUID=$(blkid -s UUID -o value /dev/${DISK}1)
BOOT_UUID=$(blkid -s UUID -o value /dev/${DISK}2)
ROOT_UUID=$(blkid -s UUID -o value /dev/vg0/rootlv)
HOME_UUID=$(blkid -s UUID -o value /dev/vg0/homelv)
SWAP_UUID=$(blkid -s UUID -o value /dev/vg0/swaplv)

# Vérification si tous les UUID ont été trouvés
if [[ -z "$BOOT_UUID" || -z "$EFI_UUID" || -z "$ROOT_UUID" || -z "$HOME_UUID" || -z "$SWAP_UUID" ]]; then
    echo "Erreur : Impossible de récupérer tous les UUID. Vérifiez que les partitions existent."
    exit 1
fi

# Ajouter les nouvelles entrées avec UUID
echo "UUID=${BOOT_UUID}           /boot           ext4            defaults,noatime        0 2" >> /etc/fstab
echo "UUID=${EFI_UUID}            /boot/EFI       vfat            defaults                0 0" >> /etc/fstab
echo "UUID=${ROOT_UUID}           /               ext4            defaults,noatime        0 1" >> /etc/fstab
echo "UUID=${HOME_UUID}           /home           ext4            defaults,noatime        0 2" >> /etc/fstab
echo "UUID=${SWAP_UUID}           none            swap            sw                      0 0" >> /etc/fstab


echo "=== Configurer le réseau et le hostname ==="
echo "$HOSTNAME" > /etc/conf.d/hostname
echo "127.0.0.1 $HOSTNAME localhost" >> /etc/hosts

echo "=== Configurer les locales ==="
echo "fr_FR.UTF-8 UTF-8" > /etc/locale.gen
locale-gen

eselect locale set fr_FR.UTF-8
env-update && source /etc/profile

echo "=== Configurer le fuseau horaire ==="
echo "Europe/Paris" > /etc/timezone
emerge --config sys-libs/timezone-data

echo "=== Installer le chargeur d'amorçage ==="
if [ -d /sys/firmware/efi ]; then
    echo "Le système utilise le mode UEFI."
    echo 'GRUB_PLATFORMS="efi-64"' >> /etc/portage/make.conf
    emerge -av sys-boot/grub
    mount -o remount,rw /sys/firmware/efi/efivars
    grub-install --target=x86_64-efi --efi-directory=/boot/EFI

else
    echo "Le système utilise le mode BIOS."
    echo 'GRUB_PLATFORMS="pc"' >> /etc/portage/make.conf
    emerge -av sys-boot/grub
    grub-install /dev/$DISK
fi

echo "=== Configurer le kernel ==="
echo "sys-kernel/installkernel dracut grub" >> /etc/portage/package.use/installkernel

# Installer les outils de base
emerge -av sys-kernel/installkernel lvm2 linux-firmware

/etc/init.d/lvm start
rc-update add lvm boot

emerge -av sys-kernel/linux-firmware
emerge -av sys-kernel/gentoo-sources
emerge -av sys-apps/pciutils sys-apps/usbutils

eselect kernel list
eselect kernel set 1

cd /usr/src/linux

make mrproper
make defconfig
make menuconfig

# Compilation du noyau avec le support LUKS et LVM
genkernel --luks --lvm --busybox --menuconfig all



# Finaliser l'installation
passwd  # Définir un mot de passe pour root
EOF

# Démonter les systèmes de fichiers
umount -l /mnt/gentoo/dev{/shm,/pts,}
umount -R /mnt/gentoo
swapoff /dev/vg0/swap

echo "Installation terminée ! Vous pouvez redémarrer."
