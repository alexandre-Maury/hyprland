#!/bin/bash

# Script stage3.sh

set -e  # Quitte immédiatement en cas d'erreur.

source fonction.sh 
source config.sh  # Importation des configurations

# Vérifier si le montage est correct
if ! mountpoint -q /mnt; then
    log_msg ERROR "La partition root n'est pas montée sur /mnt. Impossible de continuer."
    exit 1
fi

# Téléchargement du stage3
log_msg INFO "=== Téléchargement de l'archive stage3 ==="
wget https://distfiles.gentoo.org/releases/amd64/autobuilds/20240929T163611Z/stage3-amd64-systemd-20240929T163611Z.tar.xz -O stage3-amd64.tar.xz

# Extraction du stage3
log_msg INFO "Extraction du stage3..."
tar xpvf stage3-amd64.tar.xz --xattrs-include='*.*' --numeric-owner --overwrite || { echo "Échec de l'extraction de stage3"; exit 1; }
rm stage3-amd64.tar.xz

# Copie du repo.conf
log_msg INFO "=== Configuration de Portage Rsync Repo ==="
mkdir --parents /mnt/etc/portage/repos.conf
cp /mnt/usr/share/portage/config/repos.conf /mnt/etc/portage/repos.conf/gentoo.conf

log_msg INFO "=== Configuration du fichier /mnt/etc/portage/make.conf ==="

echo 'COMMON_FLAGS="-O2 -pipe -march=native"' >> /mnt/etc/portage/make.conf
echo 'CFLAGS="${COMMON_FLAGS}"' >> /mnt/etc/portage/make.conf
echo 'CXXFLAGS="${COMMON_FLAGS}"' >> /mnt/etc/portage/make.conf
echo 'FCFLAGS="${COMMON_FLAGS}"' >> /mnt/etc/portage/make.conf
echo 'FFLAGS="${COMMON_FLAGS}"' >> /mnt/etc/portage/make.conf
echo 'USE=""' >> /mnt/etc/portage/make.conf
echo 'MAKEOPTS="-j${NUM_CORES}"' >> /mnt/etc/portage/make.conf
echo 'L10N="${LANGUAGE}"' >> /mnt/etc/portage/make.conf
echo 'VIDEO_CARDS="fbdev vesa intel i915 nvidia nouveau radeon amdgpu radeonsi virtualbox vmware qxl"' >> /mnt/etc/portage/make.conf
echo 'INPUT_DEVICES="libinput synaptics keyboard mouse joystick wacom"' >> /mnt/etc/portage/make.conf
echo 'EMERGE_DEFAULT_OPTS="--quiet-build=y"' >> /mnt/etc/portage/make.conf
echo 'PORTAGE_SCHEDULING_POLICY="idle"' >> /mnt/etc/portage/make.conf
echo 'ACCEPT_KEYWORDS="amd64"' >> /mnt/etc/portage/make.conf
echo 'ACCEPT_LICENSE="*"' >> /mnt/etc/portage/make.conf
echo 'SYNC="rsync://rsync.gentoo.org/gentoo-portage"' >> /mnt/etc/portage/make.conf
echo 'FEATURES="buildpkg"' >> /mnt/etc/portage/make.conf
echo 'PORTAGE_NICENESS=19' >> /mnt/etc/portage/make.conf
echo 'PORTAGE_TMPDIR="/var/tmp"' >> /mnt/etc/portage/make.conf
echo 'GENTOO_MIRRORS="http://ftp.snt.utwente.nl/pub/os/linux/gentoo/ http://mirror.leaseweb.com/gentoo/"' >> /mnt/etc/portage/make.conf
echo 'DISTDIR="/var/cache/distfiles"' >> /mnt/etc/portage/make.conf
echo 'PKGDIR="/var/cache/binpkgs"' >> /mnt/etc/portage/make.conf
echo 'CHOST="x86_64-pc-linux-gnu"' >> /mnt/etc/portage/make.conf

if [[ "$(uname -m)" == "x86_64" ]]; then
    echo "CPU_FLAGS_X86_64=\"${CPU_FLAGS}\"" >> /mnt/etc/portage/make.conf
else
    echo "CPU_FLAGS_X86=\"${CPU_FLAGS}\"" >> /mnt/etc/portage/make.conf
fi

if [[ "${PART_UEFI}" == "y" ]]; then
    log_msg INFO "=== Installation de GRUB pour UEFI dans /mnt/etc/portage/make.conf ==="
    echo "GRUB_PLATFORMS=\"efi-64\"" >> /mnt/etc/portage/make.conf
else
    log_msg INFO "=== Installation de GRUB pour MBR dans /mnt/etc/portage/make.conf ==="
    echo "GRUB_PLATFORMS=\"pc\"" >> /mnt/etc/portage/make.conf
fi

# Copie du DNS
log_msg INFO "=== Copie du DNS ==="
cp -L /etc/resolv.conf /mnt/etc

# Créer le fichier fstab
log_msg INFO "=== Création du fichier /mnt/etc/fstab ==="
log_msg WARN "=== Nous allons utiliser genfstab d'Arch Linux pour générer le fichier fstab ==="
genfstab -U /mnt >> /mnt/etc/fstab

# # Ajouter l'entrée EFI si UEFI est utilisé
# if [[ ${PART_UEFI} == "y" ]]; then
#     echo "${BLOCK_DEVICE}1   /boot           vfat    defaults,noatime        0 2" >> /etc/fstab
#     echo "${BLOCK_DEVICE}2   /root           ext4    defaults,noatime        0 1" >> /etc/fstab
#     echo "${BLOCK_DEVICE}3   /home           ext4    defaults,noatime        0 2" >> /etc/fstab
# else
#     echo "${BLOCK_DEVICE}1   /boot           ext4    defaults,noatime        0 2" >> /etc/fstab
#     echo "${BLOCK_DEVICE}2   /root           ext4    defaults,noatime        0 1" >> /etc/fstab
#     echo "${BLOCK_DEVICE}3   /home           ext4    defaults,noatime        0 1" >> /etc/fstab
# fi
# echo "/swap                  none            swap    sw                      0 0" >> /etc/fstab

log_msg INFO "=== Montez les systèmes de fichiers nécessaires avant de chrooter dans Gentoo ==="
mount -t proc none /mnt/proc
mount --rbind /dev /mnt/dev
mount --rbind /sys /mnt/sys


log_msg INFO "=== Entrer dans l'environnement Gentoo avec chroot ==="
chroot /mnt /bin/bash << EOF
source /etc/profile
export PS1="(chroot) ${PS1}"
emerge-webrsync
emerge --sync
emerge -1 sys-apps/portage

log_msg INFO "=== OPTIONNEL (RECOMMANDÉ) : Reconstruire les paquets avec de nouveaux drapeaux USE ==="
emerge -auDN @world

log_msg INFO "=== Configuration des locales ===" 
echo ${LOCALE} >> /etc/locale.gen
locale-gen
localectl set-locale LANG=${LOCALE}

log_msg INFO "=== Configuration du clavier ===" 
localectl set-keymap ${KEYMAP}

log_msg INFO "=== Configuration du nom d'hôte ===" 
# echo "hostname=${HOSTNAME}" > /etc/conf.d/hostname
hostnamectl set-hostname ${HOSTNAME}
# echo "127.0.1.1 ${HOSTNAME}.localdomain ${HOSTNAME}" >> /etc/hosts
echo "127.0.0.1 localhost ${HOSTNAME}" >> /etc/hosts

log_msg INFO "=== Définir le fuseau horaire ===" 
# echo ${TIMEZONE} > /etc/timezone
# emerge --config sys-libs/timezone-data
timedatectl set-timezone ${TIMEZONE}
timedatectl set-ntp true

log_msg INFO "=== Installer le noyau et les outils système ==="
emerge gentoo-sources linux-firmware genkernel grub:2 os-prober dosfstools

log_msg INFO "=== Configurer le réseau Systemd ==="
echo '[Match]' >> /etc/systemd/network/20-wired.network
echo 'Name=${NETWORK_INTERFACE}' >> /etc/systemd/network/20-wired.network
echo '[Network]' >> /etc/systemd/network/20-wired.network
echo 'DHCP=yes' >> /etc/systemd/network/20-wired.network

systemctl enable systemd-networkd.service
systemctl enable systemd-resolved.service

log_msg INFO "=== Configurer et compiler le noyau ==="
genkernel --menuconfig all

log_msg INFO "=== Configurer et installer Grub ==="
echo 'GRUB_DISABLE_OS_PROBER=false' >> /etc/default/grub
echo 'GRUB_CMDLINE_LINUX="init=/usr/lib/systemd/systemd"' >> /etc/default/grub

if [[ ${PART_UEFI} == "y" ]]; then
    log_msg INFO "Système UEFI détecté. Installation de GRUB pour UEFI."

    grub-install --target=x86_64-efi --efi-directory=/boot    
    grub-mkconfig -o /boot/grub/grub.cfg

else
    log_msg INFO "Système BIOS détecté. Installation de GRUB pour BIOS."
    
    grub-install --target=i386-pc ${BLOCK_DEVICE}
    grub-mkconfig -o /boot/grub/grub.cfg
fi

exit
EOF

