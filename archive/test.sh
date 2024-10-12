#!/bin/bash

# 1. Partitionnement du disque
echo "Partitionnement du disque en EFI, root et home"
parted -s /dev/sda mklabel gpt
parted -s /dev/sda mkpart primary fat32 1MiB 101MiB
parted -s /dev/sda set 1 esp on
parted -s /dev/sda mkpart primary ext4 101MiB 70.1GiB
parted -s /dev/sda mkpart primary ext4 70.1GiB 100%

# 2. Création des systèmes de fichiers
echo "Création des systèmes de fichiers sur /dev/sda1 (EFI), /dev/sda2 (root) et /dev/sda3 (home)"
mkfs.fat -F32 /dev/sda1
mkfs.ext4 /dev/sda2
mkfs.ext4 /dev/sda3

# 3. Montage des partitions
echo "Montage des partitions sur /mnt/gentoo"
mount /dev/sda2 /mnt/gentoo
mkdir -p /mnt/gentoo/boot/EFI
mount /dev/sda1 /mnt/gentoo/boot/EFI
mkdir -p /mnt/gentoo/home
mount /dev/sda3 /mnt/gentoo/home

# 4. Création et activation du swap
echo "Création du fichier swap de 2Go et activation"
dd if=/dev/zero of=/mnt/gentoo/swap bs=1G count=2
chmod 600 /mnt/gentoo/swap
mkswap /mnt/gentoo/swap
swapon /mnt/gentoo/swap

# 5. Téléchargement et extraction de l'archive stage 3
echo "Téléchargement et extraction du stage 3"
cd /mnt/gentoo
wget https://distfiles.gentoo.org/releases/amd64/autobuilds/20240929T163611Z/stage3-amd64-systemd-20240929T163611Z.tar.xz
tar xvpf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner

# 6. Configuration du fichier make.conf
echo "Configuration du fichier /etc/portage/make.conf"
cat <<EOF > /mnt/gentoo/etc/portage/make.conf
COMMON_FLAGS="-O2 -pipe -march=native"
CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="\${COMMON_FLAGS}"
MAKEOPTS="-j$(nproc)"
L10N="fr"
VIDEO_CARDS="fbdev vesa intel i915 nvidia nouveau radeon amdgpu radeonsi virtualbox vmware qxl"
INPUT_DEVICES="libinput synaptics keyboard mouse joystick wacom"
EMERGE_DEFAULT_OPTS="\${EMERGE_DEFAULT_OPTS} --quiet-build=y"
PORTAGE_SCHEDULING_POLICY="idle"
GENTOO_MIRRORS="https://gentoo.mirrors.ovh.net/gentoo-distfiles/ http://ftp.free.fr/mirrors/ftp.gentoo.org/"
EOF

# 7. Sélection des miroirs
echo "Sélection des miroirs"
# mirrorselect -i -o >> /mnt/gentoo/etc/portage/make.conf

# 8. Configuration réseau et systèmes de montage
echo "Copie des fichiers de configuration réseau et systèmes de montage"
cp -L /etc/resolv.conf /mnt/gentoo/etc/
mount -t proc /proc /mnt/gentoo/proc
mount --rbind /dev /mnt/gentoo/dev
mount --rbind /sys /mnt/gentoo/sys

# 9. Chroot dans l'environnement Gentoo
echo "Chroot dans le système Gentoo"
chroot /mnt/gentoo /bin/bash <<EOF
env-update && source /etc/profile
export PS1="[chroot] \$PS1"

# 10. Mise à jour des paquets et sélection du profil systemd
echo "Mise à jour des paquets et sélection du profil systemd"
emerge-webrsync
eselect profile set 22 # Default systemd

# 11. Initialisation de la machine ID
echo "Initialisation de machine-id"
systemd-machine-id-setup

# 12. Installation de cpuid2cpuflags
echo "Installation de cpuid2cpuflags"
emerge -av app-portage/cpuid2cpuflags

# 13. Ajout des CPU_FLAGS_X86 dans make.conf
echo "Ajout des CPU_FLAGS_X86 dans make.conf"
CPU_FLAGS_X86=\$(cpuid2cpuflags)
echo "CPU_FLAGS_X86=\"\${CPU_FLAGS_X86}\"" >> /etc/portage/make.conf

# 14. Acceptation des licences
echo "Acceptation des licences propriétaires"
mkdir /etc/portage/package.license
echo "*/* *" >> /etc/portage/package.license/custom

# 15. Mise à jour du world
echo "Mise à jour du système"
emerge -avuDN @world

# 16. Configuration du fichier fstab
echo "Configuration du fichier /etc/fstab"
cat <<EOF > /etc/fstab
/dev/sda2               /               ext4            defaults,noatime         0 1
/dev/sda3               /home           ext4            defaults,noatime         0 2
/swap                   none            swap            sw                      0 0
/dev/sda1               /boot/EFI       vfat            defaults                 0 0
EOF

# 17. Installation de GRUB pour UEFI
echo "Installation de GRUB avec support UEFI"
echo 'GRUB_PLATFORMS="efi-64"' >> /etc/portage/make.conf
emerge -av sys-boot/grub
grub-install --target=x86_64-efi --efi-directory=/boot/EFI

# 18. Remonter efivars en lecture/écriture si nécessaire
echo "Remontage d'efivars si nécessaire"
mount -o remount,rw /sys/firmware/efi/efivars

# 19. Configuration de GRUB avec systemd
echo "Configuration de GRUB pour systemd"
sed -i 's/^#GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="init=\/lib\/systemd\/systemd"/' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

# 20. Installation du noyau Gentoo binaire
echo "Installation du noyau Gentoo binaire"
emerge -av sys-kernel/gentoo-kernel-bin

# 21. Configuration du réseau avec systemd
echo "Configuration du réseau avec systemd"
cat <<EOF > /etc/systemd/network/50-dhcp.network
[Match]
Name=en*

[Network]
DHCP=yes
EOF
systemctl enable systemd-networkd.service

# 22. Définition du mot de passe root
echo "Définition du mot de passe root"
passwd

# 23. Sortie du chroot et redémarrage
exit
EOF

# 24. Préparation au redémarrage
echo "Préparation au redémarrage du système"
umount -l /mnt/gentoo/dev{/shm,/pts,}
umount -l /mnt/gentoo{/boot/EFI,/proc,/sys,/home,}
swapoff /mnt/gentoo/swap

echo "Redémarrage du système"
reboot
