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