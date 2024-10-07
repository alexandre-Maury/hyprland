#!/bin/bash

############################### Formatage + Création des partitions ###############################

# Nettoyage du disque si aucun système d'exploitation détecté
clean_disk() {
    echo "Aucun autre système détecté, nettoyage complet du disque."

    if [ ! -b "/dev/$DISK" ]; then
        echo "Le disque /dev/$DISK n'existe pas."
        exit 1
    fi

    # wipefs --force --all /dev/$DISK || { echo "Erreur lors du nettoyage du disque"; exit 1; }
    sgdisk --zap-all /dev/$DISK
}


# Détection automatique du disque principal (en excluant les périphériques amovibles)
echo "Détection du disque principal..."
DISK=$(lsblk -dno NAME,TYPE | awk '$2 == "disk" {print $1}' | head -n 1)  # Récupère uniquement le nom du disque
echo "Disque détecté : /dev/$DISK"

# Vérification de l'existence du disque
if [ -z "$DISK" ]; then
    echo "Aucun disque principal trouvé."
    exit 1
fi

# Nettoyage du disque si nécessaire
clean_disk




# ############################### Installation du systeme ###############################

# # Mise à jour de l'horloge système
# echo "Synchronisation de l'horloge système..."
# timedatectl set-ntp true || { echo "Échec de la synchronisation de l'horloge"; exit 1; }

# # Téléchargement et extraction de l'archive Gentoo
# echo "Téléchargement et extraction de Gentoo..."
# wget https://bouncer.gentoo.org/fetch/root/all/releases/amd64/autobuilds/latest-stage3-amd64-systemd.txt -O stage3-amd64.txt
# STAGE3_URL=$(grep -v '^#' stage3-amd64.txt | awk '{print $1}')
# wget https://bouncer.gentoo.org/fetch/root/all/releases/amd64/autobuilds/${STAGE3_URL} -O stage3-amd64.tar.xz
# tar xpvf stage3-amd64.tar.xz --xattrs-include='*.*' --numeric-owner -C /mnt/gentoo

# # Monter les partitions nécessaires
# echo "Montage des partitions pour l'installation..."
# mount --types proc /proc /mnt/gentoo/proc || { echo "Erreur lors du montage de /proc"; exit 1; }
# mount --rbind /sys /mnt/gentoo/sys || { echo "Erreur lors du montage de /sys"; exit 1; }
# mount --make-rslave /mnt/gentoo/sys || { echo "Erreur lors de la mise à jour de /sys"; exit 1; }
# mount --rbind /dev /mnt/gentoo/dev || { echo "Erreur lors du montage de /dev"; exit 1; }
# mount --make-rslave /mnt/gentoo/dev || { echo "Erreur lors de la mise à jour de /dev"; exit 1; }

# # Copie de la configuration réseau pour qu'elle soit disponible dans le chroot
# cp /etc/resolv.conf /mnt/gentoo/etc/

# # Entrée dans l'environnement chroot
# echo "Entrée dans l'environnement chroot..."
# chroot /mnt/gentoo /bin/bash << "EOL"

# # Mise à jour des variables d'environnement
# source /etc/profile
# export PS1="(chroot) ${PS1}"

# # Monter le boot
# mkdir -p /boot/efi

# # Configurer le fuseau horaire
# echo "Europe/Paris" > /etc/timezone
# emerge --config sys-libs/timezone-data

# # Configuration des locales
# echo "fr_FR.UTF-8 UTF-8" >> /etc/locale.gen
# locale-gen
# eselect locale set fr_FR.utf8
# env-update && source /etc/profile

# # Mettre à jour l'environnement
# env-update && source /etc/profile

# # Synchroniser le système Portage
# echo "Synchronisation du dépôt Portage..."
# emerge --sync

# # Mise à jour du profil
# eselect profile list
# eselect profile set 1  # Choix du profil par défaut (par exemple, profil desktop)

# # Mise à jour du système de base (optionnel)
# emerge --ask --verbose --update --deep --newuse @world

# # Installation du noyau Linux
# echo "Installation du noyau Linux..."
# emerge --ask sys-kernel/gentoo-sources

# # Configuration du noyau
# cd /usr/src/linux
# make menuconfig  # Configuration du noyau à la main

# # Compilation et installation du noyau
# make && make modules_install
# make install

# # Installation des outils de base
# emerge --ask sys-apps/util-linux sys-apps/net-tools

# # Installation de GRUB
# emerge --ask sys-boot/grub

# # Configuration de GRUB
# grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Gentoo
# grub-mkconfig -o /boot/grub/grub.cfg

# # Sortir de l'environnement chroot
# exit
# EOL

# # Démontage des partitions
# echo "Démontage des partitions..."
# umount -R /mnt/gentoo || { echo "Erreur lors du démontage des partitions"; exit 1; }

# echo "Installation terminée. Vous pouvez maintenant redémarrer votre système."
