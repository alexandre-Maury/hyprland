#!/usr/bin/env bash

# script functions.sh

# Vérifie et installe un package si absent
check_and_install() {
    local package="$1"
    if ! command -v "$package" &> /dev/null; then
        if command -v apt &> /dev/null; then
            log_info "Installation de $package via apt"
            apt install -y "$package"
        elif command -v emerge &> /dev/null; then
            log_info "Installation de $package via emerge"
            emerge "$package"
        elif command -v pacman &> /dev/null; then
            log_info "Installation de $package via pacman"
            pacman -S --noconfirm "$package"
        fi
    fi
}

# Confirmation d'une action
prompt_confirm() {
    local prompt="$1"
    read -r -p "$prompt " response
    [[ "$response" =~ ^(y|Y|yes|YES)$ ]]
}

# Saisie avec valeur par défaut
prompt_value() {
    local prompt="$1"
    local default_value="$2"

    read -p "$prompt [$default_value]: " value
    echo "${value:-$default_value}"
}

log_colors()
{
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    LIGHT_CYAN='\033[0;96m'
    RESET='\033[0m'
}

log_it()
{
    local log_status=''
    local log_color=''
    local log_message="$*"


    case ${LOG_LEVEL_FUNCTION} in
        "SUCCESS")
            log_color=${GREEN}
            log_status='SUCCESS'
            ;;
        "WARNING")
            log_color=${YELLOW}
            log_status='WARNING'
            ;;
        "ERROR")
            log_color=${RED}
            log_status='ERROR'
            ;;
        "INFO")
            log_color=${LIGHT_CYAN}
            log_status='INFO'
            ;;
    esac

    DATE="$(date +"%Y-%m-%d %H:%M:%S")"
    if [ -n "${log_message}" ]; then
        printf "%b[ %-11s ] %s: %s%b\\n" "${log_color}" "${log_status}" "${DATE}" "${log_message}" "${RESET}"
    fi
}

log_success() { LOG_LEVEL_FUNCTION="SUCCESS" ; log_it "$*"; }
log_warning() { LOG_LEVEL_FUNCTION="WARNING" ; log_it "$*"; }
log_error() { LOG_LEVEL_FUNCTION="ERROR" ; log_it "$*"; }
log_info() { LOG_LEVEL_FUNCTION="INFO" ; log_it "$*"; }
log_colors