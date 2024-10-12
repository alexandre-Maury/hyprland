#!/usr/bin/env bash

# script chroot.sh

set -e  # Quitte immédiatement en cas d'erreur.

source config.sh # Inclure le fichier de configuration.
source functions.sh  # Charge les fonctions définies dans le fichier fonction.sh.

chmod +x *.sh # Rendre les scripts exécutables.

##############################################################################
## Preparing environment                                                      
##############################################################################
log_info "Préparation du nouvel environnement"
source /etc/profile
export PS1="(chroot) ${PS1}"
log_success "TERMINÉ"

##############################################################################
## Configure portage                                                     
##############################################################################
log_info "Installation d'un instantané du dépôt ebuild de Gentoo depuis le web"
emerge-webrsync
log_success "Installation d'un instantané du dépôt ebuild terminée"

log_info "Mise à jour de l'ensemble @world"
emerge --quiet --update --deep --newuse @world
log_success "Mise à jour de l'ensemble @world terminée"

log_info "Configuration de VIDEO_CARDS dans make.conf + installation des drivers"
GPU="$(lspci | grep VGA)"
if [[ $(echo "${GPU}" | grep -q -i intel; echo $?) == 0 ]]; then
    echo 'VIDEO_CARDS="intel fbdev vesa"' >> /etc/portage/make.conf
elif [[ "$(echo "${GPU}" | grep -q -i nvidia; echo $?)" == 0 ]]; then 
    echo 'VIDEO_CARDS="nvidia nouveau fbdev vesa"' >> /etc/portage/make.conf
    emerge --quiet x11-drivers/nvidia-drivers
elif [[ "$(echo "${GPU}" | grep -q -i amd; echo $?)" == 0 ]]; then 
    echo 'VIDEO_CARDS="amdgpu radeonsi radeon fbdev vesa"' >> /etc/portage/make.conf
fi
log_success "Configuration de VIDEO_CARDS terminée."

##############################################################################
## Setting the timezone                                                    
##############################################################################
log_info "Configuration du fuseau horaire"
echo "${TIMEZONE}" > /etc/timezone
emerge --config sys-libs/timezone-data
log_success "Configuration du fuseau horaire terminée."

##############################################################################
## Setting the timezone                                                    
##############################################################################
log_info "Configuration des locales"
echo "${LOCALE}" >> /etc/locale.gen
locale-gen
    
# create file
echo "LANG=\"${LANG}\"" > /etc/env.d/02locale
echo "LC_COLLATE=\"${LANG}\"" > /etc/env.d/02locale

env-update && source /etc/profile && export PS1="(chroot) ${PS1}"
log_success "Configuration des locales terminée."

##############################################################################
## Configure and install kernel                                                   
##############################################################################
log_info "Configurer et installer le noyau"
echo "# Accepting the license for linux-firmware" > /etc/portage/package.license

# shellcheck disable=SC2129
echo "sys-kernel/linux-firmware linux-fw-redistributable" >> /etc/portage/package.license
echo "" >> /etc/portage/package.license
echo "# Accepting any license that permits redistribution" >> /etc/portage/package.license
echo "sys-kernel/linux-firmware @BINARY-REDISTRIBUTABLE" >> /etc/portage/package.license

log_info "Installation du firmware Linux"
emerge --quiet sys-kernel/linux-firmware
if [[ $(lscpu | grep "^Model name" | grep -q -i intel; echo $?) == 0 ]]; then
    emerge --quiet sys-firmware/intel-microcode
    emerge --quiet x11-drivers/xf86-video-intel
fi

log_info "Intallation du kernel"
emerge --quiet sys-kernel/installkernel-gentoo
emerge --quiet sys-kernel/gentoo-kernel

emerge --depclean

log_success "Configuration et installation du kernel terminée"


##############################################################################
## Generating the fstab                                                 
##############################################################################
log_info "Génération du fstab"
emerge --quiet sys-fs/genfstab
genfstab -U / >> /etc/fstab
log_success "Configuration fstab terminée"

##############################################################################
## Generate hostname                                                
##############################################################################
log_info "Génération du hostname"
echo "${HOSTNAME}" > /etc/hostname
log_success "Génération du hostname terminée"

##############################################################################
## Enable networking                                                
##############################################################################
log_info "Activation du réseau"
echo '[Match]' >> /etc/systemd/network/20-wired.network
echo "Name=${INTERFACE}" >> /etc/systemd/network/20-wired.network
echo '[Network]' >> /etc/systemd/network/20-wired.network
echo 'DHCP=yes' >> /etc/systemd/network/20-wired.network

systemctl enable systemd-networkd.service
systemctl enable systemd-resolved.service
log_success "Activation du réseau terminée"

##############################################################################
## Installing grub and creating configuration                                               
##############################################################################
log_info "Installation et configuration de grub"

if [[ "${MODE}" == "UEFI" ]]; then
    echo 'GRUB_PLATFORMS="efi-64"' >> /etc/portage/make.conf
    emerge --quiet sys-boot/grub
    grub-install --target=x86_64-efi --efi-directory=/efi
	grub-mkconfig -o /boot/grub/grub.cfg

elif [[ "${MODE}" == "BIOS" ]]; then
    emerge --quiet sys-boot/grub
	grub-install /dev/"${DISK}"
	grub-mkconfig -o /boot/grub/grub.cfg

else
	log_error "An error occured at grub step. Exiting..."
	exit 1
fi

log_success "Installation et configuration de grub terminée"

##############################################################################
## Change root password                                              
##############################################################################
log_info "Changer le mot de passe root"
while ! passwd ; do
    sleep 1
done

log_success "Changer le mot de passe root terminée"

##############################################################################
## Set user and password                                               
##############################################################################
log_info "Configuration du compte utilisateur"

NAME=""

while [ -z "${NAME}" ]; do
    printf "Entrez le nom de l'utilisateur local :"
    read -r NAME
done

log_info "Ajout de l'utilisateur aux groupes users, audio, video et wheel"
useradd -m -G wheel,users,audio,video -s /bin/bash "${NAME}"

log_info "Ajout au fichier sudoers"
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

log_info "Configuration du mot de passe utilisateur"
while ! passwd "${NAME}"; do
    sleep 1
done

log_success "Configuration du compte utilisateur terminée"


##############################################################################
## quit                                               
##############################################################################
exit