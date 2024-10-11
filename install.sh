#!/usr/bin/env bash

# script install.sh

set -e  # Quitte immédiatement en cas d'erreur.

source config.sh # Inclure le fichier de configuration.
source functions.sh  # Charge les fonctions définies dans le fichier fonction.sh.


chmod +x *.sh # Rendre les scripts exécutables.


##############################################################################
## Check internet                                                          
##############################################################################
log_info "Vérifiez la connexion Internet"
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

# Demander à l'utilisateur de choisir une option : numéro ou saisie manuelle
while [[ -z "$(echo "${LIST}" | grep "  ${OPTION})")" && -z "${OPTION}" ]]; do
    printf "Choisissez un disque pour la suite de l'installation (ex : 1) ou entrez le nom du disque (ex : sda) : "
    read -r OPTION

    # Vérifier si l'utilisateur a entré un numéro ou un nom de disque valide
    if [[ -n "$(echo "${LIST}" | grep "  ${OPTION})")" ]]; then
        # L'utilisateur a choisi un disque dans la liste par numéro
        export DISK="$(echo "${LIST}" | grep "  ${OPTION})" | awk '{print $2}')"
        break
    elif [[ -n "$(lsblk -d -n | grep -v -e "loop" -e "sr" | awk '{print $1}' | grep "^${OPTION}$")" ]]; then
        # L'utilisateur a entré un nom de disque valide manuellement
        export DISK="${OPTION}"
        break
    else
        # Si aucune option n'est valide, on redemande
        log_error "Option invalide. Veuillez entrer un numéro valide ou le nom d'un disque."
        OPTION=""
    fi
done

echo "vous avez choisi $DISK"


##############################################################################
## Select part                                                          
##############################################################################
log_info "Sélectionner les tailles de vos partitions :"

if [[ -n $(ls /sys/firmware/efi/efivars 2>/dev/null) ]];then

    export MODE="UEFI"
    echo "vous est en mode : $MODE"

else

    export MODE="BIOS"
    echo "vous est en mode : $MODE"

fi