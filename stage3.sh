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

log_msg INFO "=== Entrer dans le namespace systemd ==="
sed -i -e 's/^root:\*/root:/' /mnt/etc/shadow # Supprimer le mot de passe root avant d'entrer dans le namespace systemd

systemd-nspawn -bD /mnt /bin/bash << EOF # Entrer dans le namespace systemd en utilisant systemd-nspawn
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

log_msg INFO "=== Quitter l'espace de noms Systemd ===" 
poweroff
EOF

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

log_msg INFO "=== Configuration du fichier /etc/portage/make.conf ==="

echo 'COMMON_FLAGS="-O2 -pipe -march=native"' >> /etc/portage/make.conf
echo 'CFLAGS="${COMMON_FLAGS}"' >> /etc/portage/make.conf
echo 'CXXFLAGS="${COMMON_FLAGS}"' >> /etc/portage/make.conf
echo 'FCFLAGS="${COMMON_FLAGS}"' >> /etc/portage/make.conf
echo 'FFLAGS="${COMMON_FLAGS}"' >> /etc/portage/make.conf
echo 'USE=""' >> /etc/portage/make.conf
echo 'MAKEOPTS="-j${NUM_CORES}"' >> /etc/portage/make.conf
echo 'L10N="${LANGUAGE}"' >> /etc/portage/make.conf
echo 'VIDEO_CARDS="fbdev vesa intel i915 nvidia nouveau radeon amdgpu radeonsi virtualbox vmware qxl"' >> /etc/portage/make.conf
echo 'INPUT_DEVICES="libinput synaptics keyboard mouse joystick wacom"' >> /etc/portage/make.conf
echo 'EMERGE_DEFAULT_OPTS="--quiet-build=y"' >> /etc/portage/make.conf
echo 'PORTAGE_SCHEDULING_POLICY="idle"' >> /etc/portage/make.conf
echo 'ACCEPT_KEYWORDS="amd64"' >> /etc/portage/make.conf
echo 'ACCEPT_LICENSE="*"' >> /etc/portage/make.conf
echo 'SYNC="rsync://rsync.gentoo.org/gentoo-portage"' >> /etc/portage/make.conf
echo 'FEATURES="buildpkg"' >> /etc/portage/make.conf
echo 'PORTAGE_NICENESS=19' >> /etc/portage/make.conf
echo 'PORTAGE_TMPDIR="/var/tmp"' >> /etc/portage/make.conf
echo 'GENTOO_MIRRORS="http://ftp.snt.utwente.nl/pub/os/linux/gentoo/ http://mirror.leaseweb.com/gentoo/"' >> /etc/portage/make.conf
echo 'DISTDIR="/var/cache/distfiles"' >> /etc/portage/make.conf
echo 'PKGDIR="/var/cache/binpkgs"' >> /etc/portage/make.conf
echo 'CHOST="x86_64-pc-linux-gnu"' >> /etc/portage/make.conf

if [[ "$(uname -m)" == "x86_64" ]]; then
    echo "CPU_FLAGS_X86_64=\"${CPU_FLAGS}\"" >> /etc/portage/make.conf
else
    echo "CPU_FLAGS_X86=\"${CPU_FLAGS}\"" >> /etc/portage/make.conf
fi

if [[ "${PART_UEFI}" == "y" ]]; then
    log_msg INFO "=== Installation de GRUB pour UEFI dans /etc/portage/make.conf ==="
    echo "GRUB_PLATFORMS=\"efi-64\"" >> /etc/portage/make.conf
else
    log_msg INFO "=== Installation de GRUB pour MBR dans /etc/portage/make.conf ==="
    echo "GRUB_PLATFORMS=\"pc\"" >> /etc/portage/make.conf
fi

log_msg INFO "=== OPTIONNEL (RECOMMANDÉ) : Reconstruire les paquets avec de nouveaux drapeaux USE ==="
emerge -auDN @world

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





# # Changement de racine (chroot)
# log_msg INFO "=== Changement de racine (chroot) ==="
# chroot /mnt/ /bin/bash << EOF

# source fonction.sh
# source config.sh  # Importation des configurations

# env-update && source /etc/profile

# export PS1="[chroot] $PS1"

# # Synchronisation du dépôt ebuild Gentoo
# log_msg INFO "Synchronisation du dépôt ebuild Gentoo"
# emerge-webrsync --quiet
# emerge --sync --quiet

# eselect profile list

# mkdir /etc/portage/package.license
# echo "*/* *" >> /etc/portage/package.license/custom


# log_msg INFO "Mise à jour de l'ensemble @world"
# emerge -avuDN @world --quiet

# # Installation de linux-firmware
# emerge --quiet sys-kernel/linux-firmware

# # Installation du noyau binaire
# log_msg INFO "Installation du noyau binaire"
# emerge --quiet sys-kernel/gentoo-kernel-bin
# emerge --config sys-kernel/gentoo-kernel-bin

# log_msg INFO "Installation de dhcpcd"
# emerge --quiet net-misc/dhcpcd
# systemctl enable dhcpcd

# log_msg INFO "Installation du sans-fil"
# emerge --quiet net-wireless/iw net-wireless/wpa_supplicant

# log_msg INFO "Définition du mot de passe root" 
# echo "root:${ROOT_PASSWORD}" | chpasswd

# log_msg INFO "Installation de sudo"
# emerge --quiet app-admin/sudo

# log_msg INFO "Création de l'utilisateur ${USER}"
# # useradd -m -G users,wheel -s /bin/bash ${USER}
# # echo "${USER}:${USER_PASSWORD}" | chpasswd
# # echo "${USER} ALL=(ALL) ALL" >> /etc/sudoers

# useradd -m -G users,wheel,audio,cdrom,video,portage -s /bin/bash ${USER}
# echo "${USER}:${USER_PASSWORD}" | chpasswd


# # Installation de GRUB
# emerge --quiet sys-boot/grub
# emerge --quiet sys-boot/os-prober

# if [[ ${PART_UEFI} == "y" ]]; then
#     log_msg INFO "Système UEFI détecté. Installation de GRUB pour UEFI."
#     grub-install --target=x86_64-efi --efi-directory=/boot
    
#     # Activer os-prober dans la configuration de GRUB
#     echo 'GRUB_DISABLE_OS_PROBER=false' >> /etc/default/grub
    
#     grub-mkconfig -o /boot/grub/grub.cfg

# else
#     log_msg INFO "Système BIOS détecté. Installation de GRUB pour BIOS."
#     grub-install --target=i386-pc ${BLOCK_DEVICE}

#     # Activer os-prober dans la configuration de GRUB
#     echo 'GRUB_DISABLE_OS_PROBER=false' >> /etc/default/grub

#     grub-mkconfig -o /boot/grub/grub.cfg
# fi

# exit
# EOF

