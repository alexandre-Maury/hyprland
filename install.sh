#!/usr/bin/env bash

# script install.sh

set -e  # Quitte immédiatement en cas d'erreur.

source config.sh # Inclure le fichier de configuration.
source functions.sh  # Charge les fonctions définies dans le fichier fonction.sh.
# source disk.sh


chmod +x *.sh # Rendre les scripts exécutables.


##############################################################################
## Check internet                                                          
##############################################################################
log_prompt "INFO" && echo "Vérification de la connexion Internet" && echo ""

if ! ping -c1 -w1 1.1.1.1 > /dev/null 2>&1; then
    log_prompt "ERROR" && echo "Pas de connexion Internet"
    exit 1
else
    log_prompt "SUCCESS" && echo "Terminée" && echo ""
fi

##############################################################################
## Check apps                                                          
##############################################################################

for pkg in "${packages[@]}"; do
    check_and_install "$pkg" # S'assurer que les packages requis sont installés
done

clear 
log_prompt "INFO" && echo "Bienvenue dans le script d'installation de Gentoo !" && echo ""

##############################################################################
## Creating partionning, formatting + Mounting partitions                                                      
##############################################################################

# LIST="$(lsblk -d -n | grep -v -e "loop" -e "sr" | awk '{print $1, $4}' | nl -s") ")" 

# echo "${LIST}"
# OPTION=""

# while [[ -z "$(echo "${LIST}" | grep "  ${OPTION})")" ]]; do
#     printf "Choisissez un disque pour la suite de l'installation (ex : 1) : "
#     read -r OPTION
# done

# DISK="$(echo "${LIST}" | grep "  ${OPTION})" | awk '{print $2}')"
# log_prompt "SUCCESS" "Terminée" && echo ""

# Générer la liste des disques physiques sans les disques loop et sr (CD/DVD)
LIST="$(lsblk -d -n | grep -v -e "loop" -e "sr" | awk '{print $1, $4}' | nl -s") ")" 

if [[ -z "${LIST}" ]]; then
    log_prompt "ERROR" && echo "Aucun disque disponible pour l'installation."
    exit 1  # Arrête le script ou effectue une autre action en cas d'erreur
else
    log_prompt "INFO" && echo "Choisissez un disque pour l'installation (ex : 1) : " && echo ""
    echo "${LIST}" && echo ""
fi


# Boucle pour que l'utilisateur puisse choisir un disque ou en entrer un manuellement
OPTION=""
while [[ -z "$(echo "${LIST}" | grep "  ${OPTION})")" ]]; do
    log_prompt "INFO" && read -p "Votre Choix : " OPTION
    echo ""

    # Vérification si l'utilisateur a entré un numéro (choix dans la liste)
    if [[ -n "$(echo "${LIST}" | grep "  ${OPTION})")" ]]; then
        # Si l'utilisateur a choisi un numéro valide, récupérer le nom du disque correspondant
        DISK="$(echo "${LIST}" | grep "  ${OPTION})" | awk '{print $2}')"
        break
    else
        # Si l'utilisateur a entré quelque chose qui n'est pas dans la liste, considérer que c'est un nom de disque
        DISK="${OPTION}"
        break
    fi
done

bash disk.sh $DISK $MOUNT_POINT
clear

parted /dev/"${DISK}" print

log_prompt "SUCCESS" && echo "Terminée" && echo ""

##############################################################################
## Check config                                                         
##############################################################################

log_prompt "INFO" && echo "Vérification de la configuration :" && echo ""
echo "[ ${DISK} ]"                   "- Disque"
echo "[ ${MODE} ]"                   "- Mode"
echo "[ ${TIMEZONE} ]"               "- Fuseau horaire" 
echo "[ ${LOCALE} ]"                 "- Locale" 
echo "[ ${HOSTNAME} ]"               "- Nom d'hôte" 
echo "[ ${INTERFACE} ]"              "- Interface" 
echo "[ ${KEYMAP} ]"                 "- Disposition du clavier" 
echo "[ ${USERNAME} ]"               "- Votre utilisateur" 
echo ""

# Demande à l'utilisateur de confirmer la configuration
if ! prompt_confirm "Vérifiez que les informations ci-dessus sont correctes (Y/n)"; then
    log_prompt "ERROR" && echo "Annulation de l'installation."
    exit 0
fi

##############################################################################
## Configuring date                                                    
##############################################################################

# log_prompt "INFO" && echo "Configurer l'heure avec chrony" && echo ""
# chronyd -q
# log_prompt "SUCCESS" && echo "Terminée" && echo ""

##############################################################################
## Downloading and unarchiving stage3 tarball                                                  
##############################################################################

log_prompt "INFO" && echo "Téléchargement et décompression de l'archive stage3" && echo ""

pushd $MOUNT_POINT || exit 1

wget "${GENTOO_BASE}"
tar xpf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner
rm stage3-*.tar.xz

popd || exit 1
log_prompt "SUCCESS" && echo "Terminée" && echo ""

##############################################################################
## Configuring /etc/portage/make.conf                                                 
##############################################################################

log_prompt "INFO" && echo "Configuration du fichier /etc/portage/make.conf" && echo ""

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

log_prompt "SUCCESS" && echo "Terminée" && echo ""

##############################################################################
## Configure Gentoo ebuild repository                                                 
##############################################################################

log_prompt "INFO" && echo "Configurer le dépôt ebuild de Gentoo" && echo ""

mkdir --parents /mnt/gentoo/etc/portage/repos.conf
cp $MOUNT_POINT/usr/share/portage/config/repos.conf $MOUNT_POINT/etc/portage/repos.conf/gentoo.conf

log_prompt "SUCCESS" && echo "Terminée" && echo ""

##############################################################################
## Copying DNS info                                                 
##############################################################################
log_prompt "INFO" && echo "Copie des informations DNS" && echo ""
cp --dereference /etc/resolv.conf $MOUNT_POINT/etc/
log_prompt "SUCCESS" && echo "Terminée"  && echo ""

##############################################################################
## Mounting the necessary filesystems                                                 
##############################################################################
log_prompt "INFO" && echo "Montage des systèmes de fichiers nécessaires" && echo ""
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-slave /mnt/gentoo/run
log_prompt "SUCCESS" && echo "Terminée" && echo ""

##############################################################################
## Enter the new environment                                             
##############################################################################
log_prompt "INFO" && echo "Copie de la deuxième partie du script d'installation dans le nouvel environnement" && echo ""

cp functions.sh $MOUNT_POINT
cp config.sh $MOUNT_POINT
cp chroot.sh $MOUNT_POINT

log_prompt "INFO" && echo "Entrée dans le nouvel environnement et exécution de la deuxième partie du script" && echo ""

chroot $MOUNT_POINT /bin/bash -c "./chroot.sh $DISK"

log_prompt "SUCCESS" && echo "Terminée" && echo ""





