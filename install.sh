#!/usr/bin/env bash

# script install.sh

set -e  # Quitte immédiatement en cas d'erreur.

source config.sh # Inclure le fichier de configuration.
source functions.sh  # Charge les fonctions définies dans le fichier fonction.sh.
source disk.sh


chmod +x *.sh # Rendre les scripts exécutables.


##############################################################################
## Check internet                                                          
##############################################################################

log_info "Vérification de la connexion Internet"
if ! ping -c1 -w1 1.1.1.1 > /dev/null 2>&1; then
    log_error "Pas de connexion Internet"
    exit 1
else
    log_success "Connecté à Internet"
fi

##############################################################################
## Check apps                                                          
##############################################################################

for pkg in "${packages[@]}"; do
    check_and_install "$pkg" # S'assurer que les packages requis sont installés
done

clear 
log_info "Bienvenue dans le script d'installation de Gentoo !" # Affiche un message de bienvenue pour l'utilisateur.
echo ""

##############################################################################
## Check config                                                         
##############################################################################

log_info "Vérification de la configuration :"
echo ""
echo "[ ${DISK} ]"                   "- Disque"
echo "[ ${MODE} ]"                   "- Mode"
echo "[ ${TIMEZONE} ]"               "- Fuseau horaire" 
echo "[ ${LOCALE} ]"                 "- Locale" 
echo "[ ${HOSTNAME} ]"               "- Nom d'hôte" 
echo "[ ${INTERFACE} ]"              "- Interface" 
echo "[ ${KEYMAP} ]"                 "- Disposition du clavier" 
echo "[ ${ROOT_PASSWORD} ]"          "- Votre mot de passe ROOT" 
echo "[ ${USERNAME} ]"               "- Votre utilisateur" 
echo "[ ${USERNAME_PASSWORD} ]"      "- Votre mot de passe" 
echo ""

# Demande à l'utilisateur de confirmer la configuration
if ! prompt_confirm "Vérifiez que les informations ci-dessus sont correctes (Y/n)"; then
    log_warning "Annulation de l'installation."
    exit 0
fi

##############################################################################
## Creating partionning, formatting + Mounting partitions                                                      
##############################################################################
log_info "Exécution du script disk.sh"
# read DISK <<< $(bash disk.sh)
bash disk.sh

##############################################################################
## Configuring date                                                    
##############################################################################

log_info "Configurer l'heure avec chrony"
chronyd -q
log_success "TERMINÉ"

##############################################################################
## Downloading and unarchiving stage3 tarball                                                  
##############################################################################

log_info "Téléchargement et décompression de l'archive stage3"
pushd $MOUNT_POINT || exit 1

wget "${GENTOO_BASE}"
tar xpf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner
rm stage3-*.tar.xz

popd || exit 1
log_success "décompression de l'archive stage3 terminé"

##############################################################################
## Configuring /etc/portage/make.conf                                                 
##############################################################################

log_info "Configuration du fichier /etc/portage/make.conf"
MAKE_CONF="$MOUNT_POINT/etc/portage/make.conf"

echo 'COMMON_FLAGS="-O2 -pipe -march=native"' >> "${MAKE_CONF}"
echo "CFLAGS=\"${COMMON_FLAGS}\"" >> "${MAKE_CONF}"
echo "CXXFLAGS=\"${COMMON_FLAGS}\"" >> "${MAKE_CONF}"
echo "USE=\"${USE}\"" >> "${MAKE_CONF}"
echo "MAKEOPTS=\"${MAKEOPTS}\"" >> "${MAKE_CONF}"
echo "LINGUAS=\"${L10N}\"" >> "${MAKE_CONF}"
echo "L10N=\"${L10N}\"" >> "${MAKE_CONF}"
echo "INPUT_DEVICES=\"${INPUT_DEVICES}\"" >> "${MAKE_CONF}"
echo "EMERGE_DEFAULT_OPTS=\"${EMERGE_DEFAULT_OPTS} --quiet-build=y\"" >> "${MAKE_CONF}"
echo 'PORTAGE_SCHEDULING_POLICY="idle"' >> "${MAKE_CONF}"
echo 'ACCEPT_LICENSE="*"' >> "${MAKE_CONF}"
echo 'ACCEPT_KEYWORDS="~amd64"' >> "${MAKE_CONF}"
echo 'GENTOO_MIRRORS="https://gentoo.mirrors.ovh.net/gentoo-distfiles/ http://ftp.free.fr/mirrors/ftp.gentoo.org/"' >> "${MAKE_CONF}"
echo 'VIDEO_CARDS="fbdev vesa intel i915 nvidia nouveau radeon amdgpu radeonsi virtualbox vmware qxl"' >> "${MAKE_CONF}"

if [[ "$(uname -m)" == "x86_64" ]]; then
    echo "CPU_FLAGS_X86_64=\"${CPU_FLAGS}\"" >> "${MAKE_CONF}"
else
    echo "CPU_FLAGS_X86=\"${CPU_FLAGS}\"" >> "${MAKE_CONF}"
fi

log_success "Configuration du fichier /etc/portage/make.conf terminé"

##############################################################################
## Configure Gentoo ebuild repository                                                 
##############################################################################

log_info "Configurer le dépôt ebuild de Gentoo"
mkdir --parents /mnt/gentoo/etc/portage/repos.conf
cp $MOUNT_POINT/usr/share/portage/config/repos.conf $MOUNT_POINT/etc/portage/repos.conf/gentoo.conf

log_success "Configurer le dépôt ebuild de Gentoo terminé"

##############################################################################
## Copying DNS info                                                 
##############################################################################
log_info "Copie des informations DNS"
cp --dereference /etc/resolv.conf $MOUNT_POINT/etc/
log_success "Copie des informations DNS terminé"

##############################################################################
## Mounting the necessary filesystems                                                 
##############################################################################
log_info "Montage des systèmes de fichiers nécessaires"
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-slave /mnt/gentoo/run
log_success "Montage des systèmes de fichiers nécessaires terminé"

##############################################################################
## Enter the new environment                                             
##############################################################################
log_info "Copie de la deuxième partie du script d'installation dans le nouvel environnement"

cp functions.sh $MOUNT_POINT
cp config.sh $MOUNT_POINT
cp chroot.sh $MOUNT_POINT

log_info "Entrée dans le nouvel environnement et exécution de la deuxième partie du script"

# chroot $MOUNT_POINT /bin/bash -c "./chroot.sh $MODE $DISK"

log_success "INSTALLATION TERMINÉ : après redémarrage lancé bash -x post_install.sh"

echo "TEST DE RENVOI : $DISK"





