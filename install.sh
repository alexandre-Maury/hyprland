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

# Afficher le disque sélectionné ou saisi manuellement
echo "Vous avez choisi : $DISK"


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