#!/bin/bash

# Script stage3.sh

set -e  # Quitte immédiatement en cas d'erreur.

source fonction.sh 

# Vérifier si le montage est correct
if ! mountpoint -q /mnt/gentoo; then
    log_msg ERROR "La partition root n'est pas montée sur /mnt/gentoo. Impossible de continuer."
    exit 1
fi

# Téléchargement du stage3
log_msg INFO "=== Téléchargement de l'archive stage3 ==="
links http://distfiles.gentoo.org/releases/amd64/autobuilds/ 
LINKS_RUNNING="true"
while [[ $LINKS_RUNNING == "true" ]]; do
    LINKS_RUNNING=$(ps -aux | grep -o '[l]inks' || true)
    sleep 2s
done

# Extraction du stage3
log_msg INFO "Extraction du stage3..."
tar xpvf stage3-*.tar.xz --xattrs-include="*.*" --numeric-owner -C /mnt/gentoo 
rm stage3-*.tar.xz

# Montage des systèmes de fichiers
log_msg INFO "=== Montage des systèmes de fichiers ==="
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount -t proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /tmp /mnt/gentoo/tmp
mount --bind /run /mnt/gentoo/run 


# Configuration de /mnt/gentoo/etc/portage/make.conf
log_msg INFO "Configuration du fichier /mnt/gentoo/etc/portage/make.conf"
cat <<EOF > /mnt/gentoo/etc/portage/make.conf
COMMON_FLAGS="-O2 -pipe -march=native"
CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="\${COMMON_FLAGS}"
FCFLAGS="\${COMMON_FLAGS}"
FFLAGS="\${COMMON_FLAGS}"
MAKEOPTS="-j\$(nproc)"
L10N="${CFG_LOCALE}"
VIDEO_CARDS="fbdev vesa intel i915 nvidia nouveau radeon amdgpu radeonsi virtualbox vmware qxl"
INPUT_DEVICES="libinput synaptics keyboard mouse joystick wacom"
EMERGE_DEFAULT_OPTS="--quiet-build=y"
PORTAGE_SCHEDULING_POLICY="idle"
USE=""
ACCEPT_KEYWORDS="amd64"
SYNC="rsync://rsync.gentoo.org/gentoo-portage"
FEATURES="buildpkg"
PORTAGE_NICENESS=19
PORTAGE_TMPDIR="/var/tmp"
GENTOO_MIRRORS="http://ftp.snt.utwente.nl/pub/os/linux/gentoo/ http://mirror.leaseweb.com/gentoo/"
DISTDIR="/var/cache/distfiles"
PKGDIR="/var/cache/binpkgs"
CHOST="x86_64-pc-linux-gnu"
EOF

# Copie du DNS
log_msg INFO "=== Copie du DNS ==="
cp /etc/resolv.conf /mnt/gentoo/etc

# Changement de racine (chroot)
log_msg INFO "=== Changement de racine (chroot) ==="
chroot /mnt/gentoo /bin/bash << EOF
set -e
source fonction.sh
source /etc/profile
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
emerge --ask n --sync

# Mise à jour de l'ensemble @world (@system et @selected)
log_msg INFO "Mise à jour de l'ensemble @world"
emerge --ask n --update --deep --newuse @world

# Configuration des licences
log_msg INFO "Configuration des licences"
echo "ACCEPT_LICENSE=\"-* @FREE\"" >> /etc/portage/make.conf
echo "sys-kernel/linux-firmware @BINARY-REDISTRIBUTABLE" >> /etc/portage/package.accept_keywords

# Configuration du fuseau horaire et des locales
if [[ "\${CFG_MUSL}" == "y" ]]; then
    log_msg INFO "Configuration du fuseau horaire (musl)"
    emerge --ask n --config sys-libs/timezone-data
    echo "TZ=\"/usr/share/zoneinfo/\${CFG_TIMEZONE}\"" >> /etc/env.d/00musl

    log_msg INFO "Configuration des locales (musl)"
    echo "sys-apps/musl-locales ~amd64" > /etc/portage/package.accept_keywords/sys-apps
    emerge --ask n sys-apps/musl-locales
    echo "MUSL_LOCPATH=\"/usr/share/i18n/locales/musl\"" >> /etc/env.d/00musl
else
    log_msg INFO "Configuration du fuseau horaire (glibc)"
    echo \${CFG_TIMEZONE} > /etc/timezone
    emerge --ask n sys-libs/timezone-data

    log_msg INFO "Configuration des locales (glibc)" 
    echo "\${CFG_LOCALE}" >> /etc/locale.gen
    locale-gen
fi

log_msg INFO "Rechargement de l'environnement"
env-update && source /etc/profile && export PS1="(chroot) \${PS1}"

# Installation des sources du noyau
log_msg INFO "Installation des sources du noyau"
emerge --ask n sys-kernel/gentoo-sources

log_msg INFO "Sélection des sources du noyau"
eselect kernel list
eselect kernel set 1

# Installation de genkernel
log_msg INFO "Installation de genkernel"
emerge --ask n sys-kernel/genkernel

# Configuration de fstab
if [[ "\${CFG_PART_UEFI}" == "y" ]]; then
    log_msg INFO "Ajout de /boot/efi dans fstab"
    echo "\${CFG_BLOCK_PART}1 /boot/efi vfat defaults 0 2" >> /etc/fstab
else
    log_msg INFO "Ajout de /boot dans fstab"
    echo "\${CFG_BLOCK_PART}1 /boot ext4 defaults 0 2" >> /etc/fstab
fi

# Compilation du noyau
if [[ "\${CFG_LLVM}" == "y" ]]; then
    log_msg INFO "Compilation des sources du noyau (llvm)"
    LLVM=1 LLVM_IAS=1 genkernel all \
        --kernel-as=llvm-as \
        --kernel-ar=llvm-ar \
        --kernel-cc=clang \
        --kernel-ld=ld.lld \
        --kernel-nm=llvm-nm \
        --utils-as=llvm-as \
        --utils-ar=llvm-ar \
        --utils-cc=clang \
        --utils-cxx=clang++ \
        --utils-ld=ld.lld \
        --utils-nm=llvm-nm
else
    log_msg INFO "Compilation des sources du noyau (gcc)"
    genkernel all
fi

# Installation du système de fichiers
log_msg INFO "Ajout du swap, / et du cdrom dans fstab"
mkdir -p /mnt/cdrom
echo "\${CFG_BLOCK_PART}2 none swap sw 0 0" >> /etc/fstab
echo "\${CFG_BLOCK_PART}3 / ext4 noatime 0 1" >> /etc/fstab
echo /dev/cdrom /mnt/cdrom auto noauto,user 0 0 >> /etc/fstab

# Configuration réseau
log_msg INFO "Configuration du nom d'hôte"
echo "hostname=\"\${CFG_HOSTNAME}\"" > /etc/conf.d/hostname

log_msg INFO "Installation de netifrc"
emerge --ask n --noreplace net-misc/netifrc

log_msg INFO "Installation de dhcpcd"
emerge --ask n net-misc/dhcpcd

log_msg INFO "Installation du sans-fil"
emerge --ask n net-wireless/iw net-wireless/wpa_supplicant

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
emerge --ask n app-admin/sudo

log_msg INFO "Création de l'utilisateur \${CFG_USER}"
useradd -m -G users,wheel -s /bin/bash \${CFG_USER}
echo "\${CFG_USER}:\${CFG_USER_PASSWORD}" | chpasswd
echo "\${CFG_USER} ALL=(ALL) ALL" >> /etc/sudoers

# Installation de GRUB
if [[ "\${CFG_PART_UEFI}" == "y" ]]; then
    log_msg INFO "Installation de GRUB pour UEFI"
    emerge --ask n sys-boot/grub
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
    grub-mkconfig -o /boot/grub/grub.cfg
else
    log_msg INFO "Installation de GRUB pour MBR"
    emerge --ask n sys-boot/grub
    grub-install --target=i386-pc \${CFG_BLOCK_PART}
    grub-mkconfig -o /boot/grub/grub.cfg
fi

log_msg INFO "=== Installation terminée ==="
EOF

# Sortie du chroot
log_msg INFO "=== Sortie du chroot ==="
# exit