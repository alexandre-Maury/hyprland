#!/usr/bin/env bash

# script install.sh

set -e  # Quitte immédiatement en cas d'erreur.

source config.sh # Inclure le fichier de configuration.
source functions.sh  # Charge les fonctions définies dans le fichier fonction.sh.


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

log_info "Bienvenue dans le script d'installation de Gentoo !" # Affiche un message de bienvenue pour l'utilisateur.


##############################################################################
## Select Disk                                                          
##############################################################################

# log_info "Sélectionner le disque pour l'installation"
# # LIST="$(lsblk -d -n | grep -v "loop" | awk '{print $1, $4}' | nl -s") ")"
# LIST="$(lsblk -d -n | grep -v -e "loop" -e "sr" | awk '{print $1, $4}' | nl -s") ")" 

# echo "${LIST}"
# OPTION=""

# while [[ -z "$(echo "${LIST}" | grep "  ${OPTION})")" ]]; do
#     printf "Choisissez un disque pour la suite de l'installation (ex : 1) : "
#     read -r OPTION
# done

# export DISK="$(echo "${LIST}" | grep "  ${OPTION})" | awk '{print $2}')"
# log_success "TERMINÉ"

# Générer la liste des disques physiques sans les disques loop et sr (CD/DVD)
LIST="$(lsblk -d -n | grep -v -e "loop" -e "sr" | awk '{print $1, $4}' | nl -s") ")" 
echo "${LIST}"
OPTION=""

# Boucle pour que l'utilisateur puisse choisir un disque ou en entrer un manuellement
while [[ -z "$(echo "${LIST}" | grep "  ${OPTION})")" ]]; do
    printf "Choisissez un disque pour la suite de l'installation (ex : 1) ou entrez manuellement le nom du disque (ex : sda) : "
    read -r OPTION

    # Vérification si l'utilisateur a entré un numéro (choix dans la liste)
    if [[ -n "$(echo "${LIST}" | grep "  ${OPTION})")" ]]; then
        # Si l'utilisateur a choisi un numéro valide, récupérer le nom du disque correspondant
        export DISK="$(echo "${LIST}" | grep "  ${OPTION})" | awk '{print $2}')"
        break
    else
        # Si l'utilisateur a entré quelque chose qui n'est pas dans la liste, considérer que c'est un nom de disque
        export DISK="${OPTION}"
        break
    fi
done

log_success "TERMINÉ"

##############################################################################
## Select shred                                                         
##############################################################################

# if [[ "$SHRED" == "On" ]]; then
#     export SHRED_PASS="$(prompt_value "Nombre de passe pour le netoyage de /dev/$DISK [ par défaut : ]" "$SHRED_PASS")"
#     log_success "TERMINÉ"
# fi

if [[ "$SHRED" == "On" ]]; then
    while true; do
        # Demande à l'utilisateur de saisir le nombre de passes
        export SHRED_PASS="$(prompt_value "Nombre de passes pour le nettoyage de /dev/$DISK [par défaut : $SHRED_PASS] : " "$SHRED_PASS")"
        
        # Vérifie si la valeur saisie est un nombre
        if [[ "$SHRED_PASS" =~ ^[0-9]+$ ]]; then
            log_success "TERMINÉ"
            break  # Sort de la boucle si la saisie est correcte
        else
            log_warning "veuillez saisir un nombre valide."  # Message d'erreur
        fi
    done
fi


##############################################################################
## Select size                                                         
##############################################################################

if [[ -n $(ls /sys/firmware/efi/efivars 2>/dev/null) ]];then
    export MODE="UEFI"
    log_info "vous est en mode : $MODE"
    export EFI_SIZE="$(prompt_value "Taille de la partition EFI en MiB [ par défaut : ]" "$EFI_SIZE")"
else
    export MODE="BIOS"
    log_info "vous est en mode : $MODE"
    export MBR_SIZE="$(prompt_value "Taille de la partition BIOS en MiB [ par défaut : ]" "$MBR_SIZE")"
fi

export ROOT_SIZE="$(prompt_value "Taille de la partition Racine en GiB [ par défaut : ]" "$ROOT_SIZE")"
export HOME_SIZE="$(prompt_value "Taille de la partition Home en %  [ par défaut : ]" "$HOME_SIZE")"

if [[ "$SWAP" == "On" ]]; then
    if [[ "$SWAP_FILE" == "On" ]]; then
        export SWAP_SIZE="$(prompt_value "Taille du fichier Swap en MiB [ par défaut : ]" "$SWAP_SIZE")"
    else
        export SWAP_SIZE="$(prompt_value "Taille de la partition Swap en MiB [ par défaut : ]" "$SWAP_SIZE")"
    fi
fi

log_success "TERMINÉ"

##############################################################################
## Select config                                                         
##############################################################################

log_info "Sélectionner vos configurations systéme :"

export TIMEZONE="$(prompt_value "Fuseau horaire du système [ par défaut : ]" "$TIMEZONE")"
export LOCALE="$(prompt_value "Locale du système [ par défaut : ]" "$LOCALE")"
export HOSTNAME="$(prompt_value "Nom d'hôte du système [ par défaut : ]" "$HOSTNAME")"
export INTERFACE="$(prompt_value "Nom de l'interface réseau [ par défaut : ]" "$INTERFACE")"
export KEYMAP="$(prompt_value "Disposition du clavier à utiliser [ par défaut : ]" "$KEYMAP")"
export LANG

export ROOT_PASSWORD="$(prompt_value "Créer votre mot de passe root [ par défaut : ]" "$ROOT_PASSWORD")"
export USERNAME="$(prompt_value "Saisir votre nom d'utilisateur [ par défaut : ]" "$USERNAME")"
export USERNAME_PASSWORD="$(prompt_value "Saisir votre mot de passe [ par défaut : ]" "$USERNAME_PASSWORD")"

export COMMON_FLAGS
export CPU_FLAGS
export MAKEOPTS
export USE
export L10N
export INPUT_DEVICES

export MOUNT_POINT

log_success "TERMINÉ"

##############################################################################
## Check config                                                         
##############################################################################

log_info "Vérification de la configuration :"
echo ""
echo "- Périphérique cible : --------------------------------------" "[ /dev/${DISK} ]"
echo "- Mode Activé : ---------------------------------------------" "[ ${MODE} ]"

if [[ "${MODE}" == "UEFI" ]]; then
    echo "- Taille de la partition EFI en MiB : -------------------" "[ ${EFI_SIZE}MiB ]"
else 
    echo "- Taille de la partition BIOS en MiB : ------------------" "[ ${MBR_SIZE}MiB ]"
fi

echo "- Taille de la partition Racine en GiB : --------------------" "[ ${ROOT_SIZE}GiB ]"
echo "- Taille de la partition Home en % : ------------------------" "[ ${HOME_SIZE}% ]"

if [[ "$SWAP" == "On" ]]; then
    if [[ "$SWAP_FILE" == "On" ]]; then
        echo "- Taille du fichier swap en MiB : -------------------" "[ ${SWAP_SIZE}MiB ]"
    else
        echo "- Taille de la partition Swap en MiB : --------------" "[ ${SWAP_SIZE}MiB ]"
    fi
fi

echo "- Fuseau horaire : ------------------------------------------" "[ ${TIMEZONE} ]"
echo "- Locale : --------------------------------------------------" "[ ${LOCALE} ]"
echo "- Nom d'hôte : ----------------------------------------------" "[ ${HOSTNAME} ]"
echo "- Interface : -----------------------------------------------" "[ ${INTERFACE} ]"
echo "- Disposition du clavier : ----------------------------------" "[ ${KEYMAP} ]"
echo "- Votre mot de passe ROOT : ---------------------------------" "[ ${ROOT_PASSWORD} ]"
echo "- Votre utilisateur : ---------------------------------------" "[ ${USERNAME} ]"
echo "- Votre mot de passe : --------------------------------------" "[ ${USERNAME_PASSWORD} ]"
echo ""

# Demande à l'utilisateur de confirmer la configuration
if ! prompt_confirm "Vérifiez que les informations ci-dessus sont correctes (Y/n)"; then
    log_warning "Annulation de l'installation."
    exit 0
fi

##############################################################################
## Formatting disk                                                       
##############################################################################

if [[ "$SHRED" == "On" ]]; then

    # Lister les partitions montées
    MOUNTED_PARTITIONS=$(lsblk --noheadings --output MOUNTPOINT "/dev/${DISK}" | grep -v "^$")

    # Si des partitions sont montées, les démonter
    if [[ -n "${MOUNTED_PARTITIONS}" ]]; then
        echo "Démontage des partitions montées sur ${DISK}..."
        for partition in $(lsblk --noheadings --output NAME,MOUNTPOINT "/dev/${DISK}" | grep -v "^$" | awk '{print $1}')
        do
            umount "/dev/${partition}" && echo "Partition /dev/${partition} démontée avec succès."
        done
    else
        echo "Aucune partition montée sur ${DISK}."
    fi

    # Une fois toutes les partitions démontées, lancer shred
    echo "Lancement de shred sur ${DISK} avec ${SHRED_PASS} passes..."
    shred -n "${SHRED_PASS}" -v "${DISK}"
fi

##############################################################################
## Creating partionning, formatting + Mounting partitions                                                      
##############################################################################

# Conversion de PART_ROOT_SIZE de GiB en MiB
ROOT_SIZE_MB=$((ROOT_SIZE * 1024))

mkdir --parents $MOUNT_POINT

if [[ "${MODE}" == "UEFI" ]]; then

    log_info "Création : Table de partitions GPT"
    parted --script -a optimal /dev/"${DISK}" mklabel gpt

    log_info "Création : Partition EFI"
    parted --script -a optimal /dev/"${DISK}" mkpart primary fat32 1MiB ${EFI_SIZE}MiB # Partition EFI
    parted --script /dev/"${DISK}" set 1 esp on

    if [[ "$SWAP" == "On" ]]; then

        if [[ "$SWAP_FILE" == "On" ]]; then

            log_info "Création : Partition Racine"
            parted --script -a optimal /dev/"${DISK}" mkpart ext4 ${EFI_SIZE}MiB $((EFI_SIZE + ROOT_SIZE_MB))MiB # Partition Racine

            log_info "Création : Partition Home"
            parted --script -a optimal /dev/"${DISK}" mkpart ext4 $((EFI_SIZE + ROOT_SIZE_MB))MiB ${HOME_SIZE}%  # Partition Home

            PARTITIONS=$(lsblk --list --noheadings /dev/"${DISK}" | tail -n +2 | awk '{print $1}')

            log_info "Formatage : Partition EFI"
            BOOT_PARTITION=$(echo "$PARTITIONS" | sed -n '1p')
            mkfs.vfat -F32 /dev/"${BOOT_PARTITION}"

            log_info "Formatage : Partition ROOT"
            ROOT_PARTITION=$(echo "$PARTITIONS" | sed -n '2p')
            mkfs.ext4 -F /dev/"${ROOT_PARTITION}"

            log_info "Formatage : Partition HOME"
            HOME_PARTITION=$(echo "$PARTITIONS" | sed -n '3p')
            mkfs.ext4 -F /dev/"${HOME_PARTITION}"

            log_info "Montage : Partition Racine"
            mkdir --parents $MOUNT_POINT
            mount /dev/"${ROOT_PARTITION}" $MOUNT_POINT

            log_info "Montage : Partition Home"
            mkdir --parents $MOUNT_POINT/home
            mount /dev/"${HOME_PARTITION}" $MOUNT_POINT/home

            log_info "Montage : Partition Boot"
            mkdir --parents $MOUNT_POINT/efi
            mount /dev/"${BOOT_PARTITION}" $MOUNT_POINT/efi 

            log_info "Création : fichier Swap"
            mkdir --parents $MOUNT_POINT/swap
            fallocate -l "${SWAP_SIZE}MiB" $MOUNT_POINT/swap/swapfile 
            chmod 600 $MOUNT_POINT/swap/swapfile                            
            mkswap $MOUNT_POINT/swap/swapfile                                
            swapon $MOUNT_POINT/swap/swapfile

        else

            log_info "Création : Partition Swap"
            parted --script -a optimal /dev/"${DISK}" mkpart linux-swap ${EFI_SIZE}MiB $((EFI_SIZE + SWAP_SIZE))MiB  # Partition Swap

            log_info "Création : Partition Racine"
            parted --script -a optimal /dev/"${DISK}" mkpart ext4 $((EFI_SIZE + SWAP_SIZE))MiB ${ROOT_SIZE_MB}MiB    # Partition Racine

            log_info "Création : Partition Home"
            parted --script -a optimal /dev/"${DISK}" mkpart ext4 $((EFI_SIZE + ROOT_SIZE_MB))MiB ${HOME_SIZE}%      # Partition Home

            PARTITIONS=$(lsblk --list --noheadings /dev/"${DISK}" | tail -n +2 | awk '{print $1}')

            log_info "Formatage : Partition EFI"
            BOOT_PARTITION=$(echo "$PARTITIONS" | sed -n '1p')
            mkfs.vfat -F32 /dev/"${BOOT_PARTITION}"

            log_info "Formatage : Partition SWAP"
            SWAP_PARTITION=$(echo "$PARTITIONS" | sed -n '2p')
            mkswap /dev/"${SWAP_PARTITION}"
            swapon /dev/"${SWAP_PARTITION}"

            log_info "Formatage : Partition ROOT"
            ROOT_PARTITION=$(echo "$PARTITIONS" | sed -n '3p')
            mkfs.ext4 -F /dev/"${ROOT_PARTITION}"

            log_info "Formatage : Partition HOME"
            HOME_PARTITION=$(echo "$PARTITIONS" | sed -n '4p')
            mkfs.ext4 -F /dev/"${HOME_PARTITION}"

            log_info "Montage : Partition Racine"
            mkdir --parents $MOUNT_POINT
            mount /dev/"${ROOT_PARTITION}" $MOUNT_POINT

            log_info "Montage : Partition Home"
            mkdir --parents $MOUNT_POINT/home
            mount /dev/"${HOME_PARTITION}" $MOUNT_POINT/home

            log_info "Montage : Partition Boot"
            mkdir --parents $MOUNT_POINT/efi
            mount /dev/"${BOOT_PARTITION}" $MOUNT_POINT/efi 

            log_info "Montage : Partition Swap"
            mkdir --parents $MOUNT_POINT/swap
            mount /dev/"${SWAP_PARTITION}" $MOUNT_POINT/swap 
        fi

    else # Swap Off
        
        log_info "Création : Partition Racine"
        parted --script -a optimal /dev/"${DISK}" mkpart ext4 ${EFI_SIZE}MiB $((EFI_SIZE + ROOT_SIZE_MB))MiB # Partition Racine

        log_info "Création : Partition Home"
        parted --script -a optimal /dev/"${DISK}" mkpart ext4 $((EFI_SIZE + ROOT_SIZE_MB))MiB ${HOME_SIZE}%  # Partition Home

        PARTITIONS=$(lsblk --list --noheadings /dev/"${DISK}" | tail -n +2 | awk '{print $1}')

        log_info "Formatage : Partition EFI"
        BOOT_PARTITION=$(echo "$PARTITIONS" | sed -n '1p')
        mkfs.vfat -F32 /dev/"${BOOT_PARTITION}"

        log_info "Formatage : Partition ROOT"
        ROOT_PARTITION=$(echo "$PARTITIONS" | sed -n '2p')
        mkfs.ext4 -F /dev/"${ROOT_PARTITION}"

        log_info "Formatage : Partition HOME"
        HOME_PARTITION=$(echo "$PARTITIONS" | sed -n '3p')
        mkfs.ext4 -F /dev/"${HOME_PARTITION}" 

        log_info "Montage : Partition Racine"
        mkdir --parents $MOUNT_POINT
        mount /dev/"${ROOT_PARTITION}" $MOUNT_POINT

        log_info "Montage : Partition Home"
        mkdir --parents $MOUNT_POINT/home
        mount /dev/"${HOME_PARTITION}" $MOUNT_POINT/home

        log_info "Montage : Partition Boot"
        mkdir --parents $MOUNT_POINT/efi
        mount /dev/"${BOOT_PARTITION}" $MOUNT_POINT/efi 
    fi

else # BIOS

    log_info "Création : Table de partitions MBR"
    parted --script -a optimal /dev/"${DISK}" mklabel msdos

    log_info "Création : Table de partitions BIOS"
    parted -a optimal /dev/"${DISK}" mkpart primary ext4 1MiB ${MBR_SIZE}MiB # Partition BIOS

    if [[ "$SWAP" == "On" ]]; then

        if [[ "$SWAP_FILE" == "On" ]]; then

            log_info "Création : Partition Racine"
            parted --script -a optimal /dev/"${DISK}" mkpart ext4 ${MBR_SIZE}MiB $((MBR_SIZE + ROOT_SIZE_MB))MiB # Partition Racine

            log_info "Création : Partition Home"
            parted --script -a optimal /dev/"${DISK}" mkpart ext4 $((MBR_SIZE + ROOT_SIZE_MB))MiB ${HOME_SIZE}%  # Partition Home

            ##### j'en suis ici -> avec le formatage
            PARTITIONS=$(lsblk --list --noheadings /dev/"${DISK}" | tail -n +2 | awk '{print $1}')

            log_info "Formatage : Partition BOOT"
            BOOT_PARTITION=$(echo "$PARTITIONS" | sed -n '1p')
            mkfs.ext4 -F /dev/"${BOOT_PARTITION}"

            log_info "Formatage : Partition ROOT"
            ROOT_PARTITION=$(echo "$PARTITIONS" | sed -n '2p')
            mkfs.ext4 -F /dev/"${ROOT_PARTITION}"

            log_info "Formatage : Partition HOME"
            HOME_PARTITION=$(echo "$PARTITIONS" | sed -n '3p')
            mkfs.ext4 -F /dev/"${HOME_PARTITION}"

            log_info "Montage : Partition Racine"
            mkdir --parents $MOUNT_POINT
            mount /dev/"${ROOT_PARTITION}" $MOUNT_POINT

            log_info "Montage : Partition Home"
            mkdir --parents $MOUNT_POINT/home
            mount /dev/"${HOME_PARTITION}" $MOUNT_POINT/home

            log_info "Montage : Partition Boot"
            mkdir --parents $MOUNT_POINT/boot
            mount /dev/"${BOOT_PARTITION}" $MOUNT_POINT/boot 

            log_info "Création : fichier Swap"
            mkdir --parents $MOUNT_POINT/swap
            fallocate -l "${SWAP_SIZE}MiB" $MOUNT_POINT/swap/swapfile
            # dd if=/dev/zero of=$MOUNT_POINT/swap bs=1M count=${SWAP_SIZE}  
            chmod 600 $MOUNT_POINT/swap/swapfile                            
            mkswap $MOUNT_POINT/swap/swapfile                                
            swapon $MOUNT_POINT/swap/swapfile  

        else

            log_info "Création : Partition Swap"
            parted --script -a optimal /dev/"${DISK}" mkpart linux-swap ${MBR_SIZE}MiB $((MBR_SIZE + SWAP_SIZE))MiB  # Partition Swap

            log_info "Création : Partition Racine"
            parted --script -a optimal /dev/"${DISK}" mkpart ext4 $((MBR_SIZE + SWAP_SIZE))MiB ${ROOT_SIZE_MB}MiB    # Partition Racine

            log_info "Création : Partition Home"
            parted --script -a optimal /dev/"${DISK}" mkpart ext4 $((MBR_SIZE + ROOT_SIZE_MB))MiB ${HOME_SIZE}%      # Partition Home

            PARTITIONS=$(lsblk --list --noheadings /dev/"${DISK}" | tail -n +2 | awk '{print $1}')

            log_info "Formatage : Partition BOOT"
            BOOT_PARTITION=$(echo "$PARTITIONS" | sed -n '1p')
            mkfs.ext4 -F /dev/"${BOOT_PARTITION}"

            log_info "Formatage : Partition SWAP"
            SWAP_PARTITION=$(echo "$PARTITIONS" | sed -n '2p')
            mkswap /dev/"${SWAP_PARTITION}"
            swapon /dev/"${SWAP_PARTITION}"

            log_info "Formatage : Partition ROOT"
            ROOT_PARTITION=$(echo "$PARTITIONS" | sed -n '3p')
            mkfs.ext4 -F /dev/"${ROOT_PARTITION}"

            log_info "Formatage : Partition HOME"
            HOME_PARTITION=$(echo "$PARTITIONS" | sed -n '4p')
            mkfs.ext4 -F /dev/"${HOME_PARTITION}"

            log_info "Montage : Partition Racine"
            mkdir --parents $MOUNT_POINT
            mount /dev/"${ROOT_PARTITION}" $MOUNT_POINT

            log_info "Montage : Partition Home"
            mkdir --parents $MOUNT_POINT/home
            mount /dev/"${HOME_PARTITION}" $MOUNT_POINT/home

            log_info "Montage : Partition Boot"
            mkdir --parents $MOUNT_POINT/boot
            mount /dev/"${BOOT_PARTITION}" $MOUNT_POINT/boot 

            log_info "Montage : Partition Swap"
            mkdir --parents $MOUNT_POINT/swap
            mount /dev/"${SWAP_PARTITION}" $MOUNT_POINT/swap
        fi

    else # Swap Off

        mkdir --parents $MOUNT_POINT/{boot,home}
        
        log_info "Création : Partition Racine"
        parted --script -a optimal /dev/"${DISK}" mkpart ext4 ${MBR_SIZE}MiB $((MBR_SIZE + ROOT_SIZE_MB))MiB # Partition Racine

        log_info "Création : Partition Home"
        parted --script -a optimal /dev/"${DISK}" mkpart ext4 $((MBR_SIZE + ROOT_SIZE_MB))MiB ${HOME_SIZE}%  # Partition Home

        PARTITIONS=$(lsblk --list --noheadings /dev/"${DISK}" | tail -n +2 | awk '{print $1}')

        log_info "Formatage : Partition BOOT"
        BOOT_PARTITION=$(echo "$PARTITIONS" | sed -n '1p')
        mkfs.ext4 -F /dev/"${BOOT_PARTITION}"

        log_info "Formatage : Partition ROOT"
        ROOT_PARTITION=$(echo "$PARTITIONS" | sed -n '2p')
        mkfs.ext4 -F /dev/"${ROOT_PARTITION}"

        log_info "Formatage : Partition HOME"
        HOME_PARTITION=$(echo "$PARTITIONS" | sed -n '3p')
        mkfs.ext4 -F /dev/"${HOME_PARTITION}"

        log_info "Montage : Partition Racine"
        mkdir --parents $MOUNT_POINT
        mount /dev/"${ROOT_PARTITION}" $MOUNT_POINT

        log_info "Montage : Partition Home"
        mkdir --parents $MOUNT_POINT/home
        mount /dev/"${HOME_PARTITION}" $MOUNT_POINT/home

        log_info "Montage : Partition Boot"
        mkdir --parents $MOUNT_POINT/boot
        mount /dev/"${BOOT_PARTITION}" $MOUNT_POINT/boot 
        
    fi
  
fi

log_success "TERMINÉ"

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
log_success "TERMINÉ"

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

# echo "GENTOO_MIRRORS="http://ftp.snt.utwente.nl/pub/os/linux/gentoo/ http://mirror.leaseweb.com/gentoo/"" >> "${MAKE_CONF}"
mirrorselect -i -o >> "${MAKE_CONF}"


if [[ "$(uname -m)" == "x86_64" ]]; then
    echo "CPU_FLAGS_X86_64=\"${CPU_FLAGS}\"" >> "${MAKE_CONF}"
else
    echo "CPU_FLAGS_X86=\"${CPU_FLAGS}\"" >> "${MAKE_CONF}"
fi

log_success "TERMINÉ"

##############################################################################
## Configure Gentoo ebuild repository                                                 
##############################################################################

log_info "Configurer le dépôt ebuild de Gentoo"
mkdir --parents /mnt/gentoo/etc/portage/repos.conf
cp $MOUNT_POINT/usr/share/portage/config/repos.conf $MOUNT_POINT/etc/portage/repos.conf/gentoo.conf

log_success "TERMINÉ"

##############################################################################
## Copying DNS info                                                 
##############################################################################

log_info "Copie des informations DNS"
cp --dereference /etc/resolv.conf $MOUNT_POINT/etc/
log_success "TERMINÉ"

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
log_success "TERMINÉ"

##############################################################################
## Enter the new environment                                             
##############################################################################
log_info "Copie de la deuxième partie du script d'installation dans le nouvel environnement"
cp chroot.sh $MOUNT_POINT
cp functions.sh $MOUNT_POINT
log_success "TERMINÉ"


log_info "Entrée dans le nouvel environnement et exécution de la deuxième partie du script"
chroot $MOUNT_POINT /bin/bash -c "./chroot.sh"
log_success "INSTALLATION TERMINÉ"













# cp chroot.sh $MOUNT_POINT
# cp functions.sh $MOUNT_POINT
# cp config.sh $MOUNT_POINT
    
# # Exécution du script chroot.sh dans /mnt/gentoo
# # (cd $MOUNT_POINT && bash chroot.sh)

# log_info INFO "Installation terminée. Vous pouvez redémarrer votre machine."
# log_info INFO "Aprés redémarrage -> eselect locale list"
# log_info INFO "Aprés redémarrage -> hostnamectl"
# log_info INFO "Aprés redémarrage -> passwd" # Set root password