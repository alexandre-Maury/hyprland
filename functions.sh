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
    if ! command -v "$package" &> /dev/null; then
        if command -v apt &> /dev/null; then
            log_prompt "INFO" && echo "Installation de $package via apt" && echo ""
            apt install -y "$package"
        elif command -v emerge &> /dev/null; then
            log_prompt "INFO" && echo "Installation de $package via emerge" && echo ""
            emerge "$package"
        elif command -v pacman &> /dev/null; then
            log_prompt "INFO" && echo "Installation de $package via pacman" && echo ""
            pacman -S --noconfirm "$package"
        fi
    fi
}


# Confirmation d'une action
prompt_confirm() {
    local prompt="$1"
    # Appliquer la couleur LIGHT_CYAN au prompt et réinitialiser après la saisie
    # read -r -p "${LIGHT_CYAN}${prompt}${RESET} " response

    echo -ne "${LIGHT_CYAN} [ INFO ] $(date +"%Y-%m-%d %H:%M:%S") ==> ${RESET} ${prompt} "
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