#!/bin/bash

# Configuration des variables
DISK="/dev/sda"
CFG_PART_EFI_SIZE="100"     # Taille de la partition EFI en Mo
CFG_PART_SWAP_SIZE="4096"   # Taille de la partition swap en Mo
CFG_PART_ROOT_SIZE="10240"  # Taille de la partition root en Mo
CFG_PART_HOME_SIZE="100%"   # Le reste pour /home

# Locales françaises
LOCALE="fr_FR.UTF-8"

# Variables de stage 3
STAGE3_URL="https://bouncer.gentoo.org/fetch/root/all/releases/amd64/autobuilds/current-stage3-amd64-systemd/stage3-amd64-systemd-latest.tar.xz"
MOUNT_DIR="/mnt/gentoo"

# Partitionnement et formatage du disque
echo "Partitionnement du disque $DISK..."

parted --script "$DISK" mklabel gpt
parted --script "$DISK" mkpart primary fat32 1MiB "${CFG_PART_EFI_SIZE}MiB"
parted --script "$DISK" set 1 boot on
parted --script "$DISK" mkpart primary linux-swap "${CFG_PART_EFI_SIZE}MiB" "$((CFG_PART_EFI_SIZE + CFG_PART_SWAP_SIZE))MiB"
parted --script "$DISK" mkpart primary ext4 "$((CFG_PART_EFI_SIZE + CFG_PART_SWAP_SIZE))MiB" "$((CFG_PART_EFI_SIZE + CFG_PART_SWAP_SIZE + CFG_PART_ROOT_SIZE))MiB"
parted --script "$DISK" mkpart primary ext4 "$((CFG_PART_EFI_SIZE + CFG_PART_SWAP_SIZE + CFG_PART_ROOT_SIZE))MiB" 100%

# Formattage des partitions
echo "Formatage des partitions..."

mkfs.fat -F32 "${DISK}1"  # EFI
mkswap "${DISK}2"         # Swap
mkfs.ext4 "${DISK}3"      # Root
mkfs.ext4 "${DISK}4"      # Home

# Montage des partitions
echo "Montage des partitions..."

mount "${DISK}3" $MOUNT_DIR
mkdir -p "$MOUNT_DIR/boot/efi"
mount "${DISK}1" "$MOUNT_DIR/boot/efi"
mkdir -p "$MOUNT_DIR/home"
mount "${DISK}4" "$MOUNT_DIR/home"
swapon "${DISK}2"

# Téléchargement et extraction du stage 3
echo "Téléchargement et extraction du stage 3..."
cd $MOUNT_DIR
wget $STAGE3_URL
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner
rm stage3-*.tar.xz

# Configuration du make.conf
echo "Configuration de /mnt/gentoo/etc/portage/make.conf..."

cat <<EOF > /mnt/gentoo/etc/portage/make.conf
COMMON_FLAGS="-O2 -pipe -march=native"
CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="\${COMMON_FLAGS}"
MAKEOPTS="-j$(nproc)"
USE="systemd"
L10N="fr"
EOF

# Montage des filesystems
echo "Montage des systèmes de fichiers..."

mount -t proc /proc $MOUNT_DIR/proc
mount --rbind /sys $MOUNT_DIR/sys
mount --make-rslave $MOUNT_DIR/sys
mount --rbind /dev $MOUNT_DIR/dev
mount --make-rslave $MOUNT_DIR/dev

# Copie des DNS
cp -L /etc/resolv.conf $MOUNT_DIR/etc/

# Chroot dans le système
echo "Chroot dans le nouveau système..."
chroot $MOUNT_DIR /bin/bash <<'EOF_CHROOT'

# Mise à jour de l'environnement
source /etc/profile
export PS1="(chroot) $PS1"

# Configuration des locales
echo "Configuration des locales..."
echo "LANG=${LOCALE}" > /etc/locale.gen
locale-gen

echo "LANG=${LOCALE}" > /etc/locale.conf
export LANG=${LOCALE}

# Configuration du fuseau horaire
echo "Europe/Paris" > /etc/timezone
emerge --config sys-libs/timezone-data

# Installation de systemd
echo "Installation de systemd..."
emerge sys-apps/systemd
emerge --update --deep --newuse @world

# Activer systemd au démarrage
echo "Activation de systemd..."
ln -sf /lib/systemd/systemd /sbin/init

# Configuration du noyau
echo "Configuration du noyau..."
emerge sys-kernel/gentoo-sources
cd /usr/src/linux
make menuconfig
make && make modules_install
make install

# Installation de GRUB
echo "Installation de GRUB..."
emerge sys-boot/grub:2
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=gentoo
grub-mkconfig -o /boot/grub/grub.cfg

# Configuration de fstab
echo "Configuration de /etc/fstab..."
echo "UUID=$(blkid -s UUID -o value ${DISK}3) / ext4 defaults 0 1" >> /etc/fstab
echo "UUID=$(blkid -s UUID -o value ${DISK}1) /boot/efi vfat defaults 0 2" >> /etc/fstab
echo "UUID=$(blkid -s UUID -o value ${DISK}4) /home ext4 defaults 0 2" >> /etc/fstab
echo "UUID=$(blkid -s UUID -o value ${DISK}2) none swap sw 0 0" >> /etc/fstab

# Sortie du chroot
EOF_CHROOT

# Démontage des partitions
echo "Démontage des partitions et redémarrage..."
umount -l $MOUNT_DIR/dev{/shm,/pts,}
umount -R $MOUNT_DIR

reboot
