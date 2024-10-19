#!/usr/bin/env bash

# script functions.sh

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
LIGHT_CYAN='\033[0;96m'
RESET='\033[0m'

# Vérifie et installe un package si absent

check_and_install() {
    local package="$1"
    local install_command=""

    # Déterminer le gestionnaire de paquets disponible
    if command -v emerge &> /dev/null; then
        install_command="emerge $package"
    elif command -v pacman &> /dev/null; then
        install_command="pacman -Sy --noconfirm $package"
    else
        echo "Aucun gestionnaire de paquets compatible trouvé."
        return 1
    fi

    # Réessayer l'installation tant que le package n'est pas disponible
    until command -v "$package" &> /dev/null; do
        log_prompt "INFO" && echo "Installation de $package..."
        eval "$install_command"

        if command -v "$package" &> /dev/null; then
            log_prompt "SUCCESS" && echo "$package a été installé avec succès."
        else
            log_prompt "ERROR" && echo "L'installation de $package a échoué. Nouvelle tentative..."
        fi
    done
}


# Confirmation d'une action
prompt_confirm() {
    local prompt="$1"
    # Appliquer la couleur LIGHT_CYAN au prompt et réinitialiser après la saisie
    # read -r -p "${LIGHT_CYAN}${prompt}${RESET} " response

    echo -ne "${LIGHT_CYAN} [ INFO ] $(date +"%Y-%m-%d %H:%M:%S") ==> ${RESET} ${prompt}"
    read response

    [[ "$response" =~ ^(y|Y|yes|YES)$ ]]
}


log_prompt() {

    local log_level="$1" # INFO - WARNING - ERROR - SUCCESS
    local log_date="$(date +"%Y-%m-%d %H:%M:%S")"

    case "${log_level}" in

        "SUCCESS")
            log_color="${GREEN}"
            log_status='SUCCESS'
            ;;
        "WARNING")
            log_color="${YELLOW}"
            log_status='WARNING'
            ;;
        "ERROR")
            log_color="${RED}"
            log_status='ERROR'
            ;;
        "INFO")
            log_color="${LIGHT_CYAN}"
            log_status='INFO'
            ;;
        *)
            log_color="${RESET}" # Au cas où un niveau inconnu est utilisé
            log_status='UNKNOWN'
            ;;
    esac

    echo -ne "${log_color} [ ${log_status} ] "${log_date}" ==> ${RESET}"

}