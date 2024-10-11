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

export ROOT_PASSWORD="$(prompt_value "Créer votre mot de passe root [ par défaut : ]" "$ROOT_PASSWORD")"
export USERNAME="$(prompt_value "Saisir votre nom d'utilisateur [ par défaut : ]" "$USERNAME")"
export USERNAME_PASSWORD="$(prompt_value "Saisir votre mot de passe [ par défaut : ]" "$USERNAME_PASSWORD")"

export COMMON_FLAGS
export CPU_FLAGS
export NUM_CORES
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
    shred -n "${SHRED_PASS}" -v "/dev/${DISK}"
fi

##############################################################################
## Creating partitions                                                       
##############################################################################

# Conversion de PART_ROOT_SIZE de GiB en MiB
ROOT_SIZE_MB=$((ROOT_SIZE * 1024))

if [[ "${MODE}" == "UEFI" ]]; then

    parted --script -a optimal /dev/"${DISK}" mklabel gpt
    parted --script -a optimal /dev/"${DISK}" mkpart primary fat32 1MiB ${EFI_SIZE}MiB # Partition EFI
    parted --script /dev/"${DISK}" set 1 esp on

    if [[ "$SWAP" == "On" ]]; then
        if [[ "$SWAP_FILE" == "On" ]]; then

            log_info "Création du fichier Swap"

            parted --script -a optimal /dev/"${DISK}" mkpart ext4 ${EFI_SIZE}MiB $((EFI_SIZE + ROOT_SIZE_MB))MiB # Partition Racine
            parted --script -a optimal /dev/"${DISK}" mkpart ext4 $((EFI_SIZE + ROOT_SIZE_MB))MiB ${HOME_SIZE}%  # Partition Home

            # Création du fichier de swap
            dd if=/dev/zero of=$MOUNT_POINT/swap bs=1M count=${SWAP_SIZE}  
            chmod 600 $MOUNT_POINT/swap                            
            mkswap $MOUNT_POINT/swap                                
            swapon $MOUNT_POINT/swap  

            # PARTITIONS=$(lsblk --list --noheadings /dev/"${DISK}" | tail -n +2 | awk '{print $1}')

        else

            log_info "Création d'une partition Swap"

            # Création des partition
            parted --script -a optimal /dev/"${DISK}" mkpart linux-swap ${EFI_SIZE}MiB $((EFI_SIZE + SWAP_SIZE))MiB  # Partition Swap
            parted --script -a optimal /dev/"${DISK}" mkpart ext4 $((EFI_SIZE + SWAP_SIZE))MiB ${ROOT_SIZE_MB}MiB    # Partition Racine
            parted --script -a optimal /dev/"${DISK}" mkpart ext4 $((EFI_SIZE + ROOT_SIZE_MB))MiB ${HOME_SIZE}%      # Partition Home

            # PARTITIONS=$(lsblk --list --noheadings /dev/"${DISK}" | tail -n +2 | awk '{print $1}')
        fi

    else # Swap Off
        parted --script -a optimal /dev/"${DISK}" mkpart ext4 ${EFI_SIZE}MiB $((EFI_SIZE + ROOT_SIZE_MB))MiB # Partition Racine
        parted --script -a optimal /dev/"${DISK}" mkpart ext4 $((EFI_SIZE + ROOT_SIZE_MB))MiB ${HOME_SIZE}%  # Partition Home

        # PARTITIONS=$(lsblk --list --noheadings /dev/"${DISK}" | tail -n +2 | awk '{print $1}')
        
    fi

    # RESTE FORMATING
    PARTITIONS=$(lsblk --list --noheadings /dev/"${DISK}" | tail -n +2 | awk '{print $1}')

    echo "Vos Partition : $PARTITIONS"

    
else 

    parted --script -a optimal /dev/"${DISK}" mklabel msdos
    parted -a optimal /dev/"${DISK}" mkpart primary ext4 1MiB ${MBR_SIZE}MiB # Partition BIOS

    
fi