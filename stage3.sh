#!/bin/bash

# Script stage3.sh

set -e  # Quitte immédiatement en cas d'erreur.

source fonction.sh 
source config.sh  # Importation des configurations

# Vérifier si le montage est correct
if ! mountpoint -q /mnt/gentoo; then
    log_msg ERROR "La partition root n'est pas montée sur /mnt/gentoo. Impossible de continuer."
    exit 1
fi

# Téléchargement du stage3
log_msg INFO "=== Téléchargement de l'archive stage3 ==="
wget https://distfiles.gentoo.org/releases/amd64/autobuilds/20240929T163611Z/stage3-amd64-systemd-20240929T163611Z.tar.xz -O stage3-amd64.tar.xz

# Extraction du stage3
log_msg INFO "Extraction du stage3..."
tar xpvf stage3-amd64.tar.xz --xattrs-include='*.*' --numeric-owner --overwrite || { echo "Échec de l'extraction de stage3"; exit 1; }
rm stage3-amd64.tar.xz


# Configuration de /mnt/gentoo/etc/portage/make.conf
log_msg INFO "Configuration du fichier /mnt/gentoo/etc/portage/make.conf"
cat <<EOF > /mnt/gentoo/etc/portage/make.conf
COMMON_FLAGS="-O2 -pipe -march=native"
CFLAGS="${COMMON_FLAGS}"
CXXFLAGS="${COMMON_FLAGS}"
FCFLAGS="${COMMON_FLAGS}"
FFLAGS="${COMMON_FLAGS}"
USE=""
MAKEOPTS="-j"$(nproc)"" 
L10N="${CFG_LANGUAGE}"
VIDEO_CARDS="fbdev vesa intel i915 nvidia nouveau radeon amdgpu radeonsi virtualbox vmware qxl"
INPUT_DEVICES="libinput synaptics keyboard mouse joystick wacom"
EMERGE_DEFAULT_OPTS="--quiet-build=y"
PORTAGE_SCHEDULING_POLICY="idle"
ACCEPT_KEYWORDS="amd64"
ACCEPT_LICENSE="*"
SYNC="rsync://rsync.gentoo.org/gentoo-portage"
FEATURES="buildpkg"
PORTAGE_NICENESS=19
PORTAGE_TMPDIR="/var/tmp"
GENTOO_MIRRORS="http://ftp.snt.utwente.nl/pub/os/linux/gentoo/ http://mirror.leaseweb.com/gentoo/"
DISTDIR="/var/cache/distfiles"
PKGDIR="/var/cache/binpkgs"
CHOST="x86_64-pc-linux-gnu"
EOF

# Ajout des options CPU_FLAGS_* au fichier make.conf
CPU_FLAGS=$(grep -m1 "flags" /proc/cpuinfo | cut -d' ' -f2-)
if [[ "$(uname -m)" == "x86_64" ]]; then
    echo "CPU_FLAGS_X86_64=\"${CPU_FLAGS}\"" >> /mnt/gentoo/etc/portage/make.conf
else
    echo "CPU_FLAGS_X86=\"${CPU_FLAGS}\"" >> /mnt/gentoo/etc/portage/make.conf
fi

if [[ "${CFG_PART_UEFI}" == "y" ]]; then
    log_msg INFO "Installation de GRUB pour UEFI"
    echo "GRUB_PLATFORMS=\"efi-64\"" >> /mnt/gentoo/etc/portage/make.conf
else
    log_msg INFO "Installation de GRUB pour MBR"
    echo "GRUB_PLATFORMS=\"pc\"" >> /mnt/gentoo/etc/portage/make.conf
fi

# Copie du repo.conf
log_msg INFO "=== Copie du repo.conf ==="
mkdir -p /mnt/gentoo/etc/portage/repos.conf
cp /mnt/gentoo/usr/share/portage/config/repos.conf /mnt/gentoo/etc/portage/repos.conf/gentoo.conf

# Copie du DNS
log_msg INFO "=== Copie du DNS ==="
cp -L /etc/resolv.conf /mnt/gentoo/etc

# Montage des systèmes de fichiers
log_msg INFO "=== Montage des systèmes de fichiers ==="
mount --rbind /dev /mnt/gentoo/dev 
mount --make-rslave /mnt/gentoo/dev 
mount -t proc /proc /mnt/gentoo/proc 
mount --rbind /sys /mnt/gentoo/sys 
mount --make-rslave /mnt/gentoo/sys 
mount --rbind /tmp /mnt/gentoo/tmp 
mount --types tmpfs tmpfs /mnt/gentoo/run 

if [[ -L /dev/shm ]]; then
    rm /dev/shm
    mkdir /dev/shm
    log_msg INFO "/dev/shm a été supprimé et recréé en tant que répertoire."
fi

mount --types tmpfs --options nosuid,nodev,noexec shm /dev/shm || { log_msg ERROR "Erreur lors du montage de /dev/shm"; exit 1; }
chmod 1777 /dev/shm

# # Montage des systèmes de fichiers
# mount -t proc /proc /mnt/gentoo/proc
# mount --rbind /dev /mnt/gentoo/dev
# mount --rbind /sys /mnt/gentoo/sys

# Changement de racine (chroot)
log_msg INFO "=== Changement de racine (chroot) ==="
chroot /mnt/gentoo /bin/bash << EOF

source fonction.sh
source config.sh  # Importation des configurations

env-update && source /etc/profile

export PS1="[chroot] $PS1"

# Synchronisation du dépôt ebuild Gentoo
log_msg INFO "Synchronisation du dépôt ebuild Gentoo"
emerge-webrsync --quiet

eselect profile list

mkdir /etc/portage/package.license
echo "*/* *" >> /etc/portage/package.license/custom


log_msg INFO "Mise à jour de l'ensemble @world"
emerge -avuDN @world --quiet

log_msg INFO "Configuration des locales (glibc)" 
echo \"${CFG_LOCALE}\" >> /etc/locale.gen
locale-gen

# Configuration du fuseau horaire et des locales
log_msg INFO "Configuration du fuseau horaire (glibc)"
echo \"${CFG_TIMEZONE}\" > /etc/timezone
emerge --config sys-libs/timezone-data


log_msg INFO " Génération du fichier /etc/fstab"

if [[ \"${CFG_PART_UEFI}\" == "y" ]]; then
  # Partition EFI
  UUID=$(blkid -s UUID -o value \"${CFG_BLOCK_DEVICE}1\")
  echo "UUID=\"${UUID}\"   /boot/efi      vfat    defaults      0  2" >> /etc/fstab
else
  # Partition BOOT en mode BIOS
  UUID=$(blkid -s UUID -o value \"${CFG_BLOCK_DEVICE}1\")
  echo "UUID=\"${UUID}\"   /boot          ext4    defaults      0  2" >> /etc/fstab
fi

# Partition root
UUID=$(blkid -s UUID -o value \"${CFG_BLOCK_DEVICE}2\")
echo "UUID=\"${UUID}\"   /              ext4    defaults      0  1" >> /etc/fstab

# Fichier Swap
echo "/swap   none   swap   sw    0   0" >> /etc/fstab


# Installation de linux-firmware
emerge --quiet sys-kernel/linux-firmware

# Installation du noyau binaire
log_msg INFO "Installation du noyau binaire"
emerge --quiet sys-kernel/gentoo-kernel-bin
emerge --config sys-kernel/gentoo-kernel-bin


# Configuration réseau
log_msg INFO "Configuration du nom d'hôte"
echo "hostname=\"${CFG_HOSTNAME}\"" > /etc/conf.d/hostname

log_msg INFO "Configuration des hôtes" 
echo "127.0.0.1 localhost \"${CFG_HOSTNAME}\"" >> /etc/hosts
echo "::1       localhost \"${CFG_HOSTNAME}\"" >> /etc/hosts

log_msg INFO "Installation de dhcpcd"
emerge --quiet net-misc/dhcpcd
systemctl enable dhcpcd

log_msg INFO "Installation du sans-fil"
emerge --quiet net-wireless/iw net-wireless/wpa_supplicant

log_msg INFO "Définition du mot de passe root" 
echo "root:\"${CFG_ROOT_PASSWORD}\"" | chpasswd

log_msg INFO "Installation de sudo"
emerge --quiet app-admin/sudo

log_msg INFO "Création de l'utilisateur \"${CFG_USER}\" "
# useradd -m -G users,wheel -s /bin/bash \"${CFG_USER}\"
# echo "\"${CFG_USER}\":\"${CFG_USER_PASSWORD}\"" | chpasswd
# echo "\"${CFG_USER}\" ALL=(ALL) ALL" >> /etc/sudoers

useradd -m -G users,wheel,audio,cdrom,video,portage -s /bin/bash \"${CFG_USER}\"
echo "\"${CFG_USER}\":\"${CFG_USER_PASSWORD}\"" | chpasswd


# Installation de GRUB
emerge --quiet sys-boot/grub
if [[ \"${CFG_PART_UEFI}\" == "y" ]]; then
    log_msg INFO "Installation de GRUB pour UEFI"
    grub-install --target=x86_64-efi --efi-directory=/boot/EFI 
    grub-mkconfig -o /boot/grub/grub.cfg

else
    log_msg INFO "Installation de GRUB pour MBR"
    grub-install \"${CFG_BLOCK_DEVICE}1\"
    grub-mkconfig -o /boot/grub/grub.cfg
fi

log_msg INFO "=== Installation terminée ==="
exit
EOF