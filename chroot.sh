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
log_prompt "INFO" && echo "Préparation du nouvel environnement" && echo ""
env-update && source /etc/profile && export PS1="[chroot] $PS1"
log_prompt "SUCCESS" && echo "Terminée" && echo ""

##############################################################################
## Configure portage                                                     
##############################################################################
log_info "INFO" && echo "Installation d'un instantané du dépôt ebuild de Gentoo depuis le web" && echo ""
emerge-webrsync
log_prompt "SUCCESS" && echo "Terminée" && echo ""

##############################################################################
## Setting the locale                                                    
##############################################################################
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf



##############################################################################
## Setting the timezone                                                    
##############################################################################
log_prompt "INFO" && echo "Configuration du fuseau horaire" && echo ""
echo "${TIMEZONE}" > /etc/timezone
timedatectl set-timezone "${TIMEZONE}"
log_prompt "SUCCESS" && echo "Terminée" && echo ""

##############################################################################
## Generate hostname                                                
##############################################################################
log_prompt "INFO" && echo "Génération du hostname" && echo ""
echo "${HOSTNAME}" > /etc/hostname
hostnamectl set-hostname "${HOSTNAME}"
echo "127.0.0.1 localhost" >> /etc/hosts
log_prompt "SUCCESS" && echo "Terminée" && echo ""

##############################################################################
## Configurer profil                                                  
##############################################################################
# log_prompt "INFO" "Configuration du profil avec eselect"
# eselect profile list
# eselect profile set XX
# log_prompt "SUCCESS" "Configuration du profil avec eselect terminée"

##############################################################################
## Créer le machine-id                                                 
##############################################################################
log_prompt "INFO" && echo "Configuration du machine-id" && echo ""
systemd-machine-id-setup
log_prompt "SUCCESS" && echo "Terminée" && echo ""

##############################################################################
## Problème des logiciels non-libres (Facultatif) + dépôts binaires                                           
##############################################################################
log_prompt "INFO" && echo "Configuration des logiciels non-libres (Facultatif) + dépôts binaires" && echo ""
mkdir --parents /etc/portage/package.license
echo "*/* *" >> /etc/portage/package.license/custom

mkdir --parents /etc/portage/binrepos.conf/
echo '[binhost]' >> /etc/portage/binrepos.conf/gentoobinhost.conf
echo 'priority = 9999' >> /etc/portage/binrepos.conf/gentoobinhost.conf
echo 'sync-uri = https://distfiles.gentoo.org/releases/amd64/binpackages/23.0/x86-64/' >> /etc/portage/binrepos.conf/gentoobinhost.conf
log_prompt "SUCCESS" && echo "Terminée" && echo ""

##############################################################################
## Mise à jour du world                                  
##############################################################################
log_prompt "INFO" && echo "Mise à jour de l'ensemble @world" && echo  ""
emerge --quiet --update --deep --newuse @world
log_prompt "SUCCESS" && echo "Terminée" && echo ""

##############################################################################
## Generating the fstab                                                 
##############################################################################
log_prompt "INFO" && echo "Génération du fstab" && echo ""
emerge --quiet sys-fs/genfstab
genfstab -U / >> /etc/fstab
log_prompt "SUCCESS" && echo "Terminée" && echo ""

##############################################################################
## Installing grub and creating configuration                                               
##############################################################################
log_prompt "INFO" && echo "Installation et configuration de grub" && echo ""

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
	log_prompt "ERROR" && echo "Une erreur est survenue $MODE non reconnu"
	exit 1
fi

GRUB_CONFIG="/etc/default/grub"
sed -i 's/^#\?GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="init=\/lib\/systemd\/systemd"/' "$GRUB_CONFIG"

log_prompt "SUCCESS" && echo "Terminée" && echo ""

##############################################################################
## Configure and install kernel                                                   
##############################################################################
log_prompt "INFO" && echo "Configurer et installer le kernel" && echo ""
echo "sys-kernel/installkernel dracut grub" >> /etc/portage/package.use/installkernel

mkdir --parents /etc/portage/package.license
echo "sys-kernel/linux-firmware linux-fw-redistributable no-source-code" >> /etc/portage/package.license/custom 

emerge --quiet sys-kernel/installkernel
emerge --quiet sys-kernel/linux-firmware
emerge --quiet sys-kernel/gentoo-kernel-bin
emerge --config sys-kernel/gentoo-kernel-bin

log_prompt "SUCCESS" && echo "Terminée" && echo ""

##############################################################################
## Générer la configuration de GRUB                                           
##############################################################################
# Vérifier si le fichier grub.cfg existe
if [ -f /boot/grub/grub.cfg ]; then
    log_prompt "SUCCESS" && echo "La configuration de GRUB est déjà présente." && echo ""
else
    log_prompt "INFO" && echo "La configuration de GRUB est absente. Régénération..." && echo ""
    grub-mkconfig -o /boot/grub/grub.cfg

    if [ $? -eq 0 ]; then
        log_prompt "SUCCESS" && echo "Terminée" && echo ""
    else
        log_prompt "ERROR" && echo "Problème lors de la configuration de Grub"
        exit 1
    fi
fi

##############################################################################
## Enable networking                                                
##############################################################################
log_prompt "INFO" && echo "Activation du réseau" && echo ""
echo '[Match]' >> /etc/systemd/network/50-dhcp.network
echo "Name=${INTERFACE}" >> /etc/systemd/network/50-dhcp.network
echo '[Network]' >> /etc/systemd/network/50-dhcp.network
echo 'DHCP=yes' >> /etc/systemd/network/50-dhcp.network

systemctl enable systemd-networkd.service
systemctl enable systemd-resolved.service
log_prompt "SUCCESS" && echo "Terminée"

##############################################################################
## Installation Sudo                                  
##############################################################################
log_prompt "INFO" && echo "Installation de sudo" && echo ""
emerge --quiet app-admin/sudo
log_prompt "SUCCESS" && echo "Terminée"

##############################################################################
## Configuration de PAM                                  
##############################################################################
log_prompt "INFO" && echo "Configuration de passwdqc.conf" && echo ""

# Sauvegarde de l'ancien fichier passwdqc.conf
if [ -f "$PASSWDQC_CONF" ]; then
    cp "$PASSWDQC_CONF" "$PASSWDQC_CONF.bak"
    log_prompt "INFO" && echo "Sauvegarde du fichier existant passwdqc.conf en $PASSWDQC_CONF.bak" && echo ""
fi

# Génération du nouveau contenu de passwdqc.conf
cat <<EOF > "$PASSWDQC_CONF"
min=$MIN
max=$MAX
passphrase=$PASSPHRASE
match=$MATCH
similar=$SIMILAR
enforce=$ENFORCE
retry=$RETRY
EOF

# Vérification du succès
if [ $? -eq 0 ]; then
    log_prompt "INFO" && echo "Fichier passwdqc.conf mis à jour avec succès." && echo ""
    cat "$PASSWDQC_CONF"
    log_prompt "SUCCESS" && echo "Terminée" && echo ""

else
    log_prompt "ERROR" && echo "Erreur lors de la mise à jour du fichier passwdqc.conf." && echo ""
fi

##############################################################################
## Set root and password                                               
##############################################################################


if prompt_confirm "Souhaitez-vous modifier le mot de passe root (Y/n)"; then
    
    log_prompt "INFO" && echo "Configuration du compte root" && echo ""

    while ! passwd ; do
        sleep 1
    done

    log_prompt "SUCCESS" && echo "Terminée"
fi

##############################################################################
## Set user and password                                               
##############################################################################

# log_prompt "INFO" && echo "Les mots de passe devront désormais contenir au moins $MINLEN caractères."

log_prompt "INFO" && read -p "Saisir le nom d'utilisateur souhaité :" USERNAME 
echo ""

log_prompt "INFO" && echo "Ajout de l'utilisateur aux groupes users, audio, video et wheel" && echo ""
useradd -m -G wheel,users,audio,video -s /bin/bash "${USERNAME}"

log_prompt "INFO" && echo "Ajout du groupe wheel aux sudoers" && echo ""
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

log_prompt "INFO" && echo "Configuration du mot de passe pour l'utilisateur" && echo ""
while ! passwd "${USERNAME}"; do
    sleep 1
done

# Appliquer immédiatement l'ajout au groupe sans déconnexion
log_prompt "INFO" && echo "Appliquer les groupes sans déconnexion" && echo ""
usermod -aG wheel "${USERNAME}"
newgrp wheel

log_prompt "SUCCESS" && echo "Terminée" && echo ""


##############################################################################
## quit                                               
##############################################################################
exit


# libpwquality




