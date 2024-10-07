#!/bin/bash
set -e

source fonction.sh  # Charge les fonctions définies dans le fichier funcs.sh.

#
# Installation du stage 3
#

# Synchronisation de l'heure
# ntpd -q -g || true

log_msg INFO "=== Téléchargement et décompression de l'archive stage3 ==="
links https://www.gentoo.org/downloads/mirrors/
LINKS_RUNNING="true"
while [[ $LINKS_RUNNING == "true" ]]; do
  LINKS_RUNNING=$(ps -aux | (grep -o '[l]inks') || true)
  sleep 2s
done
tar xpvf stage3-*.tar.xz --xattrs-include="*.*" --numeric-owner
rm stage3-*.tar.xz


log_msg INFO "=== Configuration de portage (COMMON/USE) ==="
PROMPT_PORTAGE=$(prompt_accept "Configurer /etc/portage/make.conf COMMON/USE/MAKE/etc flags - y/n")
if [[ "$PROMPT_PORTAGE" == "y" ]]; then
  nano -w ./etc/portage/make.conf
  NANO_RUNNING="true"
  while [[ $NANO_RUNNING == "true" ]]; do
    NANO_RUNNING=$(ps -aux | (grep -o '[n]ano') || true)
    sleep 2s
  done
fi


log_msg INFO "=== S'assurer que le DNS fonctionne après chroot ==="
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/


log_msg INFO "=== Monter les systèmes de fichiers ==="
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-slave /mnt/gentoo/run 


log_msg INFO "=== Changement de racine (chroot) ==="
chroot /mnt/gentoo /bin/bash << EOF
set -e

source fonction.sh
source /etc/profile
export PS1="(chroot) ${PS1}"

if [[ "${CFG_PART_UEFI}" == "y" ]]; then
  log_msg INFO "Montage de la partition boot (EFI)" >> /var/log/installer.log
  mkdir -p /boot/efi
  mount ${CFG_BLOCK_PART}1 /boot/efi
else
  log_msg INFO "Montage de la partition boot (MBR)" >> /var/log/installer.log
  mount ${CFG_BLOCK_PART}1 /boot
fi

log_msg INFO "Synchronisation du dépôt ebuild Gentoo" >> /var/log/installer.log
emerge --ask n --sync

# TODO: Sélection du profil

log_msg INFO "Mise à jour de l'ensemble @world (@system et @selected)" >> /var/log/installer.log
emerge --ask n --update --deep --newuse @world

log_msg INFO "Configuration des licences" >> /var/log/installer.log
echo "ACCEPT_LICENSE=\"-* @FREE\"" >> /etc/portage/make.conf
echo "sys-kernel/linux-firmware @BINARY-REDISTRIBUTABLE" >> /etc/portage/package.license

if [[ "${CFG_MUSL}" == "y" ]]; then
  log_msg INFO "Configuration du fuseau horaire (musl)" >> /var/log/installer.log
  emerge --ask n --config sys-libs/timezone-data
  echo "TZ=\"/usr/share/zoneinfo/${CFG_TIMEZONE}\"" >> /etc/env.d/00musl

  log_msg INFO "Configuration des locales (musl)" >> /var/log/installer.log
  echo "sys-apps/musl-locales ~amd64" > /etc/portage/package.accept_keywords/sys-apps
  emerge --ask n sys-apps/musl-locales
  echo "MUSL_LOCPATH=\"/usr/share/i18n/locales/musl\"" >> /etc/env.d/00musl
else
  log_msg INFO "Configuration du fuseau horaire (glibc)" >> /var/log/installer.log
  echo ${CFG_TIMEZONE} > /etc/timezone
  emerge --ask n sys-libs/timezone-data

  log_msg INFO "Configuration des locales (glibc)" >> /var/log/installer.log
  echo "${CFG_LOCALE}" >> /etc/locale.gen
  locale-gen
fi

log_msg INFO "Rechargement de l'environnement" >> /var/log/installer.log
env-update && source /etc/profile && export PS1="(chroot) ${PS1}"

#
# Installation du firmware
#

#
# Installation du noyau
#

log_msg INFO "Installation des sources du noyau" >> /var/log/installer.log
emerge --ask n sys-kernel/gentoo-sources

log_msg INFO "Sélection des sources du noyau" >> /var/log/installer.log
eselect kernel list
eselect kernel set 1

log_msg INFO "Installation de genkernel" >> /var/log/installer.log
emerge --ask n sys-kernel/genkernel

if [[ "${CFG_PART_UEFI}" == "y" ]]; then
  log_msg INFO "Ajout de /boot/efi dans fstab" >> /var/log/installer.log
  echo "${CFG_BLOCK_PART}1 /boot/efi vfat defaults 0 2" >> /etc/fstab
else
  log_msg INFO "Ajout de /boot dans fstab" >> /var/log/installer.log
  echo "${CFG_BLOCK_PART}1 /boot ext4 defaults 0 2" >> /etc/fstab
fi

if [[ "${CFG_LLVM}" == "y" ]]; then
  log_msg INFO "Compilation des sources du noyau (llvm)" >> /var/log/installer.log
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
  log_msg INFO "Compilation des sources du noyau (gcc)" >> /var/log/installer.log
  genkernel all
fi

#
# Installation du système de fichiers
#

log_msg INFO "Ajout du swap, / et du cdrom dans fstab" >> /var/log/installer.log
mkdir -p /mnt/cdrom
echo "${CFG_BLOCK_PART}"2 none swap sw 0 0 >> /etc/fstab
echo "${CFG_BLOCK_PART}"3 / ext4 noatime 0 1 >> /etc/fstab
echo /dev/cdrom /mnt/cdrom auto noauto,user 0 0 >> /etc/fstab

#
# Installation réseau
#

log_msg INFO "Configuration du nom d'hôte" >> /var/log/installer.log
echo "hostname=\"${CFG_HOSTNAME}\"" > /etc/conf.d/hostname

log_msg INFO "Installation de netifrc" >> /var/log/installer.log
emerge --ask n --noreplace net-misc/netifrc

log_msg INFO "Installation de dhcpcd" >> /var/log/installer.log
emerge --ask n net-misc/dhcpcd

log_msg INFO "Installation du sans-fil" >> /var/log/installer.log
emerge --ask n net-wireless/iw net-wireless/wpa_supplicant

log_msg INFO "Configuration du réseau" >> /var/log/installer.log
echo "config_${CFG_NETWORK_INTERFACE}=\"dhcp\"" >> /etc/conf.d/net
ln -s /etc/init.d/net.lo /etc/init.d/net.${CFG_NETWORK_INTERFACE}
rc-update add net.${CFG_NETWORK_INTERFACE} default

log_msg INFO "Configuration des hôtes" >> /var/log/installer.log
echo "127.0.0.1 ${CFG_HOSTNAME} localhost" >> /etc/hosts

#
# Installation du système
#

log_msg INFO "Définition du mot de passe root" >> /var/log/installer.log
echo "root:${CFG_ROOT_PASSWORD}" | chpasswd


emerge --ask n app-admin/sudo
log_msg INFO "Création de l'utilisateur ${CFG_USER}" >> /var/log/installer.log
useradd -m -G users,wheel -s /bin/bash "${CFG_USER}"
log_msg INFO "Définition du mot de passe pour l'utilisateur ${CFG_USER}" >> /var/log/installer.log
echo "${CFG_USER}:${CFG_USER_PASSWORD}" | chpasswd
log_msg INFO "Ajout de ${CFG_USER} au groupe wheel pour sudo" >> /var/log/installer.log
log_msg INFO "Configuration de sudo pour le groupe wheel" >> /var/log/installer.log
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

log_msg INFO "Configuration de la carte clavier" >> /var/log/installer.log
sed -i '/^keymap/s/=.*$/=$"'"${CFG_KEYMAP}"'"/' /etc/conf.d/keymaps
rc-update add keymaps boot
rc-service keymaps restart

log_msg INFO "Installation de syslog" >> /var/log/installer.log
emerge --ask n app-admin/sysklogd
rc-update add sysklogd default

log_msg INFO "Installation de crond" >> /var/log/installer.log
emerge --ask n sys-process/cronie
rc-update add cronie default

log_msg INFO "Installation de l'indexeur de fichiers" >> /var/log/installer.log
emerge --ask n sys-apps/mlocate

log_msg INFO "Installation des outils du système de fichiers" >> /var/log/installer.log
emerge --ask n sys-fs/e2fsprogs
emerge --ask n sys-fs/dosfstools

#
# Installation du chargeur d'amorçage
#

if [[ "${CFG_PART_UEFI}" == "y" ]]; then
  log_msg INFO "Installation de grub2 avec EFI" >> /var/log/installer.log
  echo "GRUB_PLATFORMS=\"efi-64\"" >> /etc/portage/make.conf
  emerge --ask n sys-boot/grub

  log_msg INFO "Installation du chargeur de démarrage EFI" >> /var/log/installer.log
  grub-install --target=x86_64-efi --efi-directory=/boot/efi
else
  log_msg INFO "Installation de grub2" >> /var/log/installer.log
  emerge --ask n sys-boot/grub

  log_msg INFO "Installation du chargeur de démarrage MBR" >> /var/log/installer.log
  grub-install ${CFG_BLOCK_PART}
fi

log_msg INFO "Configuration du chargeur d'amorçage" >> /var/log/installer.log
grub-mkconfig -o /boot/grub/grub.cfg

EOF
