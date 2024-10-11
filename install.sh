#!/usr/bin/env bash

# script install.sh

set -e  # Quitte immédiatement en cas d'erreur.

source config.sh # Inclure le fichier de configuration.
source functions.sh  # Charge les fonctions définies dans le fichier fonction.sh.


chmod +x *.sh # Rendre les scripts exécutables.

log_info "Vérifiez la connexion Internet"
if ! ping -c1 -w1 1.1.1.1 > /dev/null 2>&1; then
    log_error "Pas de connexion Internet"
    exit 1
else
    log_success "Connecté à Internet"
fi


for pkg in "${packages[@]}"; do
    check_and_install "$pkg" # S'assurer que les packages requis sont installés
done

log_info "Bienvenue dans le script d'installation de Gentoo !" # Affiche un message de bienvenue pour l'utilisateur.

log_info "Sélectionner le disque pour l'installation"
# LIST="$(lsblk -d -n | grep -v "loop" | awk '{print $1, $4}' | nl -s") ")"
LIST="$(lsblk -d -n | grep -v -e "loop" -e "sr" | awk '{print $1, $4}' | nl -s") ")" 

echo "${LIST}"
OPTION=""

while [[ -z "$(echo "${LIST}" | grep "  ${OPTION})")" ]]; do
    printf "Choisissez un disque pour la suite de l'installation (ex : 1) : "
    read -r OPTION
done

export DISK="$(echo "${LIST}" | grep "  ${OPTION})" | awk '{print $2}')"
log_success "TERMINÉ"


echo "Vous avez choisi : $DISK  "

