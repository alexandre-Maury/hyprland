#!/usr/bin/env bash

# script chroot.sh

set -e  # Quitte immédiatement en cas d'erreur.

source functions.sh
source config.sh  

##############################################################################
## Arguments                                                     
##############################################################################
# MODE="${1}"
DISK="${1}"

chmod +x *.sh # Rendre les scripts exécutables.

##############################################################################
## Preparing environment                                                      
##############################################################################
log_info "Préparation du nouvel environnement"
env-update && source /etc/profile && export PS1="[chroot] $PS1"
log_success "TERMINÉ"

##############################################################################
## Configure portage                                                     
##############################################################################
log_info "Installation d'un instantané du dépôt ebuild de Gentoo depuis le web"
emerge-webrsync
log_success "Installation d'un instantané du dépôt ebuild terminée"

##############################################################################
## Setting the locale                                                    
##############################################################################
log_info "Configuration des locales"
echo "${LOCALE}" >> /etc/locale.gen
locale-gen
localectl set-locale "${LANG}"
localectl set-keymap "${KEYMAP}"
localectl set-x11-keymap "${KEYMAP}"
log_info "Configuration des locales terminé"

##############################################################################
## Setting the timezone                                                    
##############################################################################
log_info "Configuration du fuseau horaire"
echo "${TIMEZONE}" > /etc/timezone
timedatectl set-timezone "${TIMEZONE}"
log_info "Configuration du fuseau horaire terminé"

##############################################################################
## Generate hostname                                                
##############################################################################
log_info "Génération du hostname"
echo "${HOSTNAME}" > /etc/hostname
hostnamectl set-hostname "${HOSTNAME}"
echo "127.0.0.1 localhost" >> /etc/hosts
log_success "Génération du hostname terminée"

##############################################################################
## Configurer profil                                                  
##############################################################################
# log_info "Configuration du profil avec eselect"
# eselect profile list
# eselect profile set XX
# log_success "Configuration du profil avec eselect terminée"

##############################################################################
## Créer le machine-id                                                 
##############################################################################
log_info "Configuration du machine-id"
systemd-machine-id-setup
log_success "Configuration du machine-id terminée"

##############################################################################
## Problème des logiciels non-libres (Facultatif) + dépôts binaires                                           
##############################################################################
log_info "Configuration des logiciels non-libres (Facultatif) + dépôts binaires"
mkdir --parents /etc/portage/package.license
echo "*/* *" >> /etc/portage/package.license/custom

mkdir --parents /etc/portage/binrepos.conf/
echo '[binhost]' >> /etc/portage/binrepos.conf/gentoobinhost.conf
echo 'priority = 9999' >> /etc/portage/binrepos.conf/gentoobinhost.conf
echo 'sync-uri = https://distfiles.gentoo.org/releases/amd64/binpackages/23.0/x86-64/' >> /etc/portage/binrepos.conf/gentoobinhost.conf
log_success "Configuration des logiciels non-libres (Facultatif) + dépôts binaires"

##############################################################################
## Mise à jour du world                                  
##############################################################################
log_info "Mise à jour de l'ensemble @world"
emerge --quiet --update --deep --newuse @world
log_success "Mise à jour de l'ensemble @world terminée"

##############################################################################
## Generating the fstab                                                 
##############################################################################
log_info "Génération du fstab"
emerge --quiet sys-fs/genfstab
genfstab -U / >> /etc/fstab
log_success "Configuration fstab terminée"

##############################################################################
## Installing grub and creating configuration                                               
##############################################################################
log_info "Installation et configuration de grub"

if [[ "$MODE" == "UEFI" ]]; then
    echo 'GRUB_PLATFORMS="efi-64"' >> /etc/portage/make.conf
    emerge --quiet sys-boot/grub
    grub-install --target=x86_64-efi --efi-directory=/efi
	grub-mkconfig -o /boot/grub/grub.cfg

elif [[ "$MODE" == "BIOS" ]]; then
    echo 'GRUB_PLATFORMS="pc"' >> /etc/portage/make.conf
    emerge --quiet sys-boot/grub
	grub-install /dev/"${DISK}"
	grub-mkconfig -o /boot/grub/grub.cfg

else
	log_error "Une erreur est survenue $MODE non reconnu"
	exit 1
fi

GRUB_CONFIG="/etc/default/grub"
sed -i 's/^#\?GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="init=\/lib\/systemd\/systemd"/' "$GRUB_CONFIG"

log_success "Installation et configuration de grub terminée"

##############################################################################
## Configure and install kernel                                                   
##############################################################################
log_info "Configurer et installer le kernel"
echo "sys-kernel/installkernel dracut grub" >> /etc/portage/package.use/installkernel

mkdir --parents /etc/portage/package.license
echo "sys-kernel/linux-firmware linux-fw-redistributable no-source-code" >> /etc/portage/package.license/custom 

emerge --quiet sys-kernel/installkernel
emerge --quiet sys-kernel/linux-firmware
emerge --quiet sys-kernel/gentoo-kernel-bin
emerge --config sys-kernel/gentoo-kernel-bin

##############################################################################
## Générer la configuration de GRUB                                           
##############################################################################
# Vérifier si le fichier grub.cfg existe
if [ -f /boot/grub/grub.cfg ]; then
    echo "La configuration de GRUB est déjà présente."
else
    echo "La configuration de GRUB est absente. Régénération..."
    grub-mkconfig -o /boot/grub/grub.cfg
    if [ $? -eq 0 ]; then
        echo "Configuration de GRUB générée avec succès."
    else
        echo "Erreur lors de la régénération de la configuration de GRUB."
    fi
fi

##############################################################################
## Enable networking                                                
##############################################################################
log_info "Activation du réseau"
echo '[Match]' >> /etc/systemd/network/50-dhcp.network
echo "Name=${INTERFACE}" >> /etc/systemd/network/50-dhcp.network
echo '[Network]' >> /etc/systemd/network/50-dhcp.network
echo 'DHCP=yes' >> /etc/systemd/network/50-dhcp.network

systemctl enable systemd-networkd.service
systemctl enable systemd-resolved.service
log_success "Activation du réseau terminée"

##############################################################################
## Set user and password                                               
##############################################################################
log_info "Configuration du compte utilisateur"


NOM=""

while [ -z "${NOM}" ]; do
    printf "Entrez un nom pour l'utilisateur local : "
    read -r NOM
done

log_info "Ajout de l'utilisateur aux groupes users, audio, video et wheel"
useradd -m -G wheel,users,audio,video -s /bin/bash "${NOM}"

log_info "Ajout du groupe wheel aux sudoers"
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

log_info "Configuration du mot de passe pour l'utilisateur"
while ! passwd "${NOM}"; do
    sleep 1
done

log_success "Configuration du compte utilisateur terminée"


##############################################################################
## quit                                               
##############################################################################
exit