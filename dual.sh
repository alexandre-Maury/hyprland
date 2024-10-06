#!/bin/bash

# Vérifier si le script est exécuté avec des privilèges root
if [[ $EUID -ne 0 ]]; then
   echo "Ce script doit être exécuté en tant que root." 
   exit 1
fi

# Détection automatique du disque principal (en excluant les périphériques amovibles)
DISK=$(lsblk -nd --output NAME,SIZE,TYPE | grep "disk" | sort -k2 -h | tail -n 1 | awk '{print "/dev/" $1}')
echo "Disque détecté : $DISK"


# Demander à l'utilisateur de définir les tailles des partitions
read -p "Entrez la taille de la partition EFI - La partition EFI contient les fichiers nécessaires au démarrage du système. Taille recommandée -> 512 MiB. : " EFI_SIZE  
read -p "Entrez la taille de la partition swap - La partition swap est utilisée pour étendre la RAM virtuelle. Elle doit généralement être égale ou supérieure à la taille de la RAM physique. : " SWAP_SIZE  

# Demander à l'utilisateur s'il souhaite spécifier la taille de la partition racine ou utiliser tout l'espace disponible
read -p "Souhaitez-vous spécifier la taille de la partition racine ? (o/n) : " specify_root_size

if [[ $specify_root_size == "o" ]]; then
    # Si l'utilisateur souhaite spécifier la taille
    read -p "Entrez la taille de la partition racine (ex : 40GiB) : " ROOT_SIZE  # L'utilisateur spécifie la taille de la partition racine.
else
    # Si l'utilisateur veut utiliser tout l'espace restant pour la partition racine
    echo "La partition racine utilisera tout l'espace disque restant après la création des autres partitions."
    ROOT_SIZE="100%"  # Utiliser tout l'espace disque restant pour la partition racine.
fi

# Confirmation du formatage du disque détecté
read -p "Le disque $DISK sera formaté. Voulez-vous continuer ? [o/N] " confirm
if [[ $confirm != "o" ]]; then
    echo "Annulation du formatage."
    exit 1
fi

# Mise à jour de l'horloge système
echo "Synchronisation de l'horloge système..."
timedatectl set-ntp true || { echo "Échec de la synchronisation de l'horloge"; exit 1; }

# Partitionnement du disque
echo "Partitionnement du disque $DISK..."
parted $DISK mklabel gpt || { echo "Erreur lors de la création du label GPT"; exit 1; }
parted $DISK mkpart primary fat32 1MiB ${EFI_SIZE} || { echo "Erreur lors de la création de la partition EFI"; exit 1; }
parted $DISK mkpart primary linux-swap ${EFI_SIZE} $((${EFI_SIZE%%MiB} + ${SWAP_SIZE%%GiB} * 1024))MiB || { echo "Erreur lors de la création de la partition swap"; exit 1; }

# Calcul de la taille de la partition racine
if [[ $ROOT_SIZE == "100%" ]]; then
    ROOT_START=$((${EFI_SIZE%%MiB} + ${SWAP_SIZE%%GiB} * 1024))  # Commence après la partition EFI et swap
    parted $DISK mkpart primary ext4 ${ROOT_START}MiB 100% || { echo "Erreur lors de la création de la partition racine"; exit 1; }
else
    ROOT_START=$((${EFI_SIZE%%MiB} + ${SWAP_SIZE%%GiB} * 1024))  # Commence après la partition EFI et swap
    parted $DISK mkpart primary ext4 ${ROOT_START}MiB $((${ROOT_START} + ${ROOT_SIZE%%GiB} * 1024))MiB || { echo "Erreur lors de la création de la partition racine"; exit 1; }
fi

# Formater les partitions
EFI_PART="${DISK}1"
SWAP_PART="${DISK}2"
ROOT_PART="${DISK}3"

echo "Formatage des partitions..."
mkfs.fat -F32 $EFI_PART || { echo "Échec du formatage de la partition EFI"; exit 1; }
mkswap $SWAP_PART || { echo "Échec du formatage de la partition swap"; exit 1; }
swapon $SWAP_PART || { echo "Échec de l'activation du swap"; exit 1; }
mkfs.ext4 $ROOT_PART || { echo "Échec du formatage de la partition racine"; exit 1; }


# Monter la partition racine
echo "Montage de la partition racine..."
mount $ROOT_PART /mnt || { echo "Échec du montage de la partition racine"; exit 1; }

# Si UEFI, monter la partition EFI
if [ -b $EFI_PART ]; then
    mkdir -p /mnt/boot/efi
    mount $EFI_PART /mnt/boot/efi || { echo "Échec du montage de la partition EFI"; exit 1; }
fi

# Téléchargement et extraction du stage3
echo "Téléchargement et extraction du stage3..."
wget https://distfiles.gentoo.org/releases/amd64/autobuilds/20240929T163611Z/stage3-amd64-systemd-20240929T163611Z.tar.xz -O /mnt/stage3.tar.xz || { echo "Échec du téléchargement de stage3"; exit 1; }
tar xpvf /mnt/stage3.tar.xz -C /mnt || { echo "Échec de l'extraction de stage3"; exit 1; }

# Chroot dans le système installé
echo "Préparation du chroot..."
mount --bind /dev /mnt/dev
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys

# Exécuter les commandes dans le chroot
echo "Chroot dans le système installé..."
chroot /mnt /bin/bash <<EOF

# Configuration du système
echo "Configuration de Portage et des locales..."
echo "GRP=notfound" >> /etc/portage/make.conf
echo "L10N=\"fr_FR.UTF-8\"" >> /etc/portage/make.conf
echo "USE=\"minimal X wayland networkmanager pulseaudio\"" >> /etc/portage/make.conf

# Générer les locales
echo "fr_FR.UTF-8 UTF-8" > /etc/locale.gen
locale-gen

# Mise à jour de Portage
emerge-webrsync || { echo "Échec de la mise à jour de Portage"; exit 1; }

# Installer le noyau et les outils de base
emerge sys-kernel/gentoo-sources sys-kernel/genkernel || { echo "Échec de l'installation du noyau"; exit 1; }
genkernel all || { echo "Échec de la génération du noyau"; exit 1; }

# Installation des pilotes vidéo en fonction du matériel détecté
if lspci | grep -i vga | grep -i nvidia; then
    emerge x11-drivers/nvidia-drivers || { echo "Échec de l'installation des pilotes NVIDIA"; exit 1; }
elif lspci | grep -i vga | grep -i intel; then
    emerge x11-drivers/xf86-video-intel || { echo "Échec de l'installation des pilotes Intel"; exit 1; }
elif lspci | grep -i vga | grep -i amd; then
    emerge x11-drivers/xf86-video-amdgpu || { echo "Échec de l'installation des pilotes AMD"; exit 1; }
else
    emerge x11-drivers/xf86-video-vesa || { echo "Échec de l'installation des pilotes par défaut"; exit 1; }
fi

# Installation de Hyprland et des dépendances
eselect repository enable guru
emaint sync -r guru
emerge gui-wm/hyprland gui-apps/hyprlock gui-apps/hypridle gui-libs/xdg-desktop-portal-hyprland gui-apps/hyprland-plugins gui-apps/hyprpaper gui-apps/hyprpicker || { echo "Échec de l'installation de Hyprland"; exit 1; }

# Installer NetworkManager pour la gestion réseau
emerge net-misc/networkmanager || { echo "Échec de l'installation de NetworkManager"; exit 1; }
systemctl enable NetworkManager

# Installer PulseAudio pour le son
emerge media-sound/pulseaudio || { echo "Échec de l'installation de PulseAudio"; exit 1; }

# Créer un utilisateur
read -p "Entrez le nom d'utilisateur à créer : " username
read -s -p "Entrez le mot de passe pour l'utilisateur : " password
echo
useradd -m -G users,wheel -s /bin/bash "\$username" || { echo "Échec de la création de l'utilisateur"; exit 1; }
echo "\$username:\$password" | chpasswd

# Installer sudo et configurer pour l'utilisateur
emerge app-admin/sudo || { echo "Échec de l'installation de sudo"; exit 1; }
echo "\$username ALL=(ALL) ALL" >> /etc/sudoers

# Installer pipx, Ansible, et autres outils
emerge dev-python/pipx dev-python/ansible app-editors/nano app-editors/vim dev-vcs/git net-misc/curl || { echo "Échec de l'installation des outils"; exit 1; }

# Configurer le fichier fstab
echo "UUID=\$(blkid -s UUID -o value $ROOT_PART) / ext4 defaults 0 1" >> /etc/fstab
echo "UUID=\$(blkid -s UUID -o value $SWAP_PART) none swap sw 0 0" >> /etc/fstab
echo "UUID=\$(blkid -s UUID -o value $EFI_PART) /boot/efi vfat defaults 0 1" >> /etc/fstab

EOF

# Fin de la configuration
echo "Installation de Gentoo terminée. Redémarrez votre système."
