#!/bin/bash

# script fonction.sh

# Vérification du nombre d'arguments d'une fonction
check_args() {
    if [[ "$1" -ne "$2" ]]; then
        log_msg ERROR "Erreur check_args: nombre d'arguments donnés $1, attendu $2."
        exit 1
    fi
}

# Fonction de log avec la date et l'heure
log_msg() {
    check_args "$#" "2"
    echo "$(date '+%d/%m/%Y %H:%M:%S') $1: $2"
}

# Confirmation d'une action
prompt_confirm() {
    local prompt="$1"
    read -r -p "$prompt " response
    [[ "$response" =~ ^(y|Y|yes|YES)$ ]]
}

# Saisie avec valeur par défaut
# prompt_value() {
#     local prompt="$1"
#     local default_value="$2"

#     read -p "$prompt [$default_value]: " value
#     echo "${value:-$default_value}"
# }

prompt_value() {
    local prompt="$1"
    local var_name="$2"

    read -p "$prompt" input
    export "$var_name=${input:-${!var_name}}"

}

# Vérifie et installe un package si absent
check_and_install() {
    local package="$1"
    if ! command -v "$package" &> /dev/null; then
        if command -v apt &> /dev/null; then
            log_msg INFO "Installation de $package via apt"
            apt install -y "$package"
        elif command -v emerge &> /dev/null; then
            log_msg INFO "Installation de $package via emerge"
            emerge "$package"
        elif command -v pacman &> /dev/null; then
            log_msg INFO "Installation de $package via pacman"
            pacman -S --noconfirm "$package"
        fi
    fi
}
