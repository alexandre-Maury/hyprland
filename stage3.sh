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
links http://distfiles.gentoo.org/releases/amd64/autobuilds/ 

# Attente de la fin du téléchargement
while pgrep -x links > /dev/null; do
    sleep 2
done

# Extraction du stage3
log_msg INFO "Extraction du stage3..."
tar xpvf stage3-*.tar.xz --xattrs-include="*.*" --numeric-owner -C /mnt/gentoo 
rm stage3-*.tar.xz

# Montage des systèmes de fichiers
log_msg INFO "=== Montage des systèmes de fichiers ==="

# Montage de /dev
mount --rbind /dev /mnt/gentoo/dev || { log_msg ERROR "Erreur lors du montage de /dev"; exit 1; }
mount --make-rslave /mnt/gentoo/dev || { log_msg ERROR "Erreur lors de la mise à jour de l'esclavage de /dev"; exit 1; }
# Montage de /proc
mount -t proc /proc /mnt/gentoo/proc || { log_msg ERROR "Erreur lors du montage de /proc"; exit 1; }
# Montage de /sys
mount --rbind /sys /mnt/gentoo/sys || { log_msg ERROR "Erreur lors du montage de /sys"; exit 1; }
mount --make-rslave /mnt/gentoo/sys || { log_msg ERROR "Erreur lors de la mise à jour de l'esclavage de /sys"; exit 1; }
# Montage de /tmp
mount --rbind /tmp /mnt/gentoo/tmp || { log_msg ERROR "Erreur lors du montage de /tmp"; exit 1; }
# Montage de /run
mount --types tmpfs tmpfs /mnt/gentoo/run || { log_msg ERROR "Erreur lors du montage de /run"; exit 1; }
# Gestion de /dev/shm
if [[ -L /dev/shm ]]; then
    rm /dev/shm
    mkdir /dev/shm
    log_msg INFO "/dev/shm a été supprimé et recréé en tant que répertoire."
fi
# Monter /dev/shm en tant que tmpfs
mount --types tmpfs --options nosuid,nodev,noexec shm /dev/shm || { log_msg ERROR "Erreur lors du montage de /dev/shm"; exit 1; }
chmod 1777 /dev/shm


# Configuration de /mnt/gentoo/etc/portage/make.conf
log_msg INFO "Configuration du fichier /mnt/gentoo/etc/portage/make.conf"
cat <<EOF > /mnt/gentoo/etc/portage/make.conf
COMMON_FLAGS="-O2 -pipe -march=native"
CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="\${COMMON_FLAGS}"
FCFLAGS="\${COMMON_FLAGS}"
FFLAGS="\${COMMON_FLAGS}"
MAKEOPTS="-j\$(nproc)"
L10N="${CFG_LANGUAGE}"
VIDEO_CARDS="fbdev vesa intel i915 nvidia nouveau radeon amdgpu radeonsi virtualbox vmware qxl"
INPUT_DEVICES="libinput synaptics keyboard mouse joystick wacom"
EMERGE_DEFAULT_OPTS="--quiet-build=y"
PORTAGE_SCHEDULING_POLICY="idle"
USE=""
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

# Copie du DNS
log_msg INFO "=== Copie du DNS ==="
cp --dereference /etc/resolv.conf /mnt/gentoo/etc

# Changement de racine (chroot)
log_msg INFO "=== Changement de racine (chroot) ==="
chroot /mnt/gentoo /bin/bash << EOF
set -e
source fonction.sh
source config.sh  # Importation des configurations
export PS1="(chroot) \${PS1}"

# Montage des partitions boot
if [[ "\${CFG_PART_UEFI}" == "y" ]]; then
    log_msg INFO "Montage de la partition boot (EFI)"
    mkdir -p /boot/efi
    mount \${CFG_BLOCK_PART}1 /boot/efi
else
    log_msg INFO "Montage de la partition boot (MBR)"
    mount \${CFG_BLOCK_PART}1 /boot
fi

# Synchronisation du dépôt ebuild Gentoo
log_msg INFO "Synchronisation du dépôt ebuild Gentoo"
emerge-webrsync
emerge --sync

# Mise à jour de l'ensemble @world (@system et @selected)
log_msg INFO "Mise à jour de l'ensemble @world"
emerge --noreplace --update --deep --newuse @world

# Installation de linux-firmware
echo "sys-kernel/linux-firmware @BINARY-REDISTRIBUTABLE" >> /etc/portage/package.accept_keywords
emerge --noreplace sys-kernel/linux-firmware

# Configuration du fuseau horaire et des locales
log_msg INFO "Configuration du fuseau horaire (glibc)"
echo \${CFG_TIMEZONE} > /etc/timezone
emerge --noreplace sys-libs/timezone-data

log_msg INFO "Configuration des locales (glibc)" 
echo "\${CFG_LOCALE}" >> /etc/locale.gen
locale-gen

log_msg INFO "Rechargement de l'environnement"
env-update && source /etc/profile && export PS1="(chroot) \${PS1}"

# Installation des sources du noyau
log_msg INFO "Installation des sources du noyau"
emerge --noreplace sys-kernel/gentoo-sources

log_msg INFO "Sélection des sources du noyau"
eselect kernel list
eselect kernel set 1

# Installation de genkernel
log_msg INFO "Installation de genkernel"
emerge --noreplace sys-kernel/genkernel

# Configuration de fstab
log_msg INFO "Configuration de fstab"
{
    if [[ "\${CFG_PART_UEFI}" == "y" ]]; then
        echo "\${CFG_BLOCK_PART}1 /boot/efi vfat defaults 0 2"
    else
        echo "\${CFG_BLOCK_PART}1 /boot ext4 defaults 0 2"
    fi

    echo "\${CFG_BLOCK_PART}2 none swap sw 0 0"
    echo "\${CFG_BLOCK_PART}3 / ext4 noatime 0 1"
    echo /dev/cdrom /mnt/cdrom auto noauto,user 0 0
} >> /etc/fstab

# Compilation du noyau
log_msg INFO "Compilation des sources du noyau (gcc)"
genkernel all

# Configuration réseau
log_msg INFO "Configuration du nom d'hôte"
echo "hostname=\"\${CFG_HOSTNAME}\"" > /etc/conf.d/hostname

log_msg INFO "Installation de netifrc"
emerge --noreplace --noreplace net-misc/netifrc

log_msg INFO "Installation de dhcpcd"
emerge --noreplace net-misc/dhcpcd

log_msg INFO "Installation du sans-fil"
emerge --noreplace net-wireless/iw net-wireless/wpa_supplicant

log_msg INFO "Configuration du réseau"
echo "config_\${CFG_NETWORK_INTERFACE}=\"dhcp\"" >> /etc/conf.d/net
ln -s /etc/init.d/net.lo /etc/init.d/net.\${CFG_NETWORK_INTERFACE}
rc-update add net.\${CFG_NETWORK_INTERFACE} default

log_msg INFO "Configuration des hôtes" 
echo "127.0.0.1 \${CFG_HOSTNAME} localhost" >> /etc/hosts

# Installation du système
log_msg INFO "Définition du mot de passe root" 
echo "root:\${CFG_ROOT_PASSWORD}" | chpasswd

log_msg INFO "Installation de sudo"
emerge --noreplace app-admin/sudo

log_msg INFO "Création de l'utilisateur \${CFG_USER}"
useradd -m -G users,wheel -s /bin/bash \${CFG_USER}
echo "\${CFG_USER}:\${CFG_USER_PASSWORD}" | chpasswd
echo "\${CFG_USER} ALL=(ALL) ALL" >> /etc/sudoers

# Installation de GRUB
if [[ "\${CFG_PART_UEFI}" == "y" ]]; then
    log_msg INFO "Installation de GRUB pour UEFI"
    emerge --noreplace sys-boot/grub
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
    grub-mkconfig -o /boot/grub/grub.cfg
else
    log_msg INFO "Installation de GRUB pour MBR"
    emerge --noreplace sys-boot/grub
    grub-install --target=i386-pc \${CFG_BLOCK_PART}
    grub-mkconfig -o /boot/grub/grub.cfg
fi

log_msg INFO "=== Installation terminée ==="
EOF