#!/usr/bin/env bash

# script functions.sh

# Vérifie et installe un package si absent
check_and_install() {
    local package="$1"
    if ! command -v "$package" &> /dev/null; then
        if command -v apt &> /dev/null; then
            log_info "${YELLOW}Installation de $package via apt${RESET}"
            apt install -y "$package"
        elif command -v emerge &> /dev/null; then
            log_info "${YELLOW}Installation de $package via emerge${RESET}"
            emerge "$package"
        elif command -v pacman &> /dev/null; then
            log_info "${YELLOW}Installation de $package via pacman${RESET}"
            pacman -S --noconfirm "$package"
        fi
    fi
}


# Confirmation d'une action
prompt_confirm() {
    local prompt="$1"
    # Appliquer la couleur LIGHT_CYAN au prompt et réinitialiser après la saisie
    # read -r -p "${LIGHT_CYAN}${prompt}${RESET} " response

    printf "%b[ %-7s ] %s: %s%b\n" "${LIGHT_CYAN}" "INFO" "$(date +"%Y-%m-%d %H:%M:%S")" "${prompt}" "${RESET}"
    read response

    [[ "$response" =~ ^(y|Y|yes|YES)$ ]]
}

# Saisie avec valeur par défaut
prompt_value() {
    local prompt="$1"
    local default_value="$2"

    # Appliquer la couleur LIGHT_CYAN au prompt et réinitialiser après la saisie
    read -p "${LIGHT_CYAN}${prompt} [${default_value}]: ${RESET}" value
    echo "${value:-$default_value}"
}


# Fonction pour définir les couleurs de log
log_colors() {
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    LIGHT_CYAN='\033[0;96m'
    RESET='\033[0m'
}

# Fonction principale de log
log_it() {
    local log_color=''
    local log_status=''
    local log_message="$*"

    case "${LOG_LEVEL_FUNCTION}" in
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

    local date_stamp
    date_stamp="$(date +"%Y-%m-%d %H:%M:%S")"

    if [ -n "${log_message}" ]; then
        printf "%b[ %-7s ] %s: %s%b\n" "${log_color}" "${log_status}" "${date_stamp}" "${log_message}" "${RESET}"
    fi
}

# Fonctions de raccourci pour chaque niveau de log
log_success() { LOG_LEVEL_FUNCTION="SUCCESS"; log_it "$@"; }
log_warning() { LOG_LEVEL_FUNCTION="WARNING"; log_it "$@"; }
log_error()   { LOG_LEVEL_FUNCTION="ERROR"; log_it "$@"; }
log_info()    { LOG_LEVEL_FUNCTION="INFO"; log_it "$@"; }

# Appel pour définir les couleurs
log_colors
