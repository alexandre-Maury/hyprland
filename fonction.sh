#!/bin/bash



# Vérifie si le nombre d'arguments fournis à une fonction est correct.
check_args() {
  if [[ "$1" -ne "$2" ]]; then
    echo "Erreur check_args, nombre d'arguments donnés : $1, attendu : $2 !"
    exit 1
  fi
}

# Affiche un message de log avec la date et l'heure actuelles.
log_msg() {
  check_args "$#" "2"  # Vérifie que la fonction reçoit bien 2 arguments.

  echo "$(date '+%d/%m/%Y %H:%M:%S') $1: $2"  # Affiche la date, l'heure, le type de log (INFO, WARN) et le message.
}

# Demande une réponse à l'utilisateur et retourne 'y' ou 'n'.
prompt_accept() {
  check_args "$#" "1"  # Vérifie que la fonction reçoit bien 1 argument.

  read -p "$1: " choice  # Demande à l'utilisateur une entrée.

  # Gère les réponses 'y', 'Y', 'yes', 'YES' comme un "oui", et tout autre choix comme un "non".
  case "$choice" in
    y|Y|yes|YES ) echo "y";;  # Retourne 'y' pour une réponse positive.
    n|N|no|NO ) echo "n";;  # Retourne 'n' pour une réponse négative.
    * ) echo "n";;  # Toute autre entrée est considérée comme un "non".
  esac
}


prompt_value() {
    local prompt="$1"
    local default_value="$2"
    read -p "$prompt [$default_value]: " value
    echo "${value:-$default_value}"
}


# Fonction pour vérifier et installer des paquets
check_and_install() {
    local package="$1"

    # Vérification de la distribution
    if command -v pacman &> /dev/null; then
        # Arch Linux ou Manjaro
        if ! pacman -Qs "$package" &> /dev/null; then
            log_msg INFO "Installation de $package sur Arch Linux"
            pacman -S --noconfirm "$package"
        fi

    elif command -v apt &> /dev/null; then
        # Debian ou Ubuntu
        if ! dpkg -l | grep -q "$package"; then
            log_msg INFO "Installation de $package sur Debian/Ubuntu"
            apt update
            apt install -y "$package"
        fi

    elif command -v dnf &> /dev/null; then
        # Fedora
        if ! dnf list installed | grep -q "$package"; then
            log_msg INFO "Installation de $package sur Fedora"
            dnf install -y "$package"
        fi

    elif command -v emerge &> /dev/null; then
        # Gentoo
        if ! equery list "$package" &> /dev/null; then
            log_msg INFO "Installation de $package sur Gentoo"
            emerge "$package"

        fi
    else
        log_msg WARN "Gestionnaire de paquets non reconnu. Veuillez installer $package manuellement avant de continuer."
        exit 1
    fi
}