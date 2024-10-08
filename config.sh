#!/bin/bash

# script config.sh

# Liste des programmes requis pour l'installation
packages=("git" "tar" "links" "curl" "wget")

# DISK=$(lsblk -dno NAME,TYPE | awk '$2 == "disk"' | head -n 1)

CFG_BLOCK_DEVICE="$(lsblk -nd -o NAME,TYPE | awk '$2 == "disk" {print "/dev/" $1}')"
CFG_PART_UEFI="y"
CFG_PART_EFI_SIZE="100" # 100 mo
CFG_FILE_SWAP_SIZE="2" 
CFG_PART_ROOT_SIZE="100%" # Le reste 
CFG_TIMEZONE="Europe/Paris"
CFG_LOCALE="fr_FR.UTF-8 UTF-8"
CFG_HOSTNAME="gentoo"
CFG_NETWORK_INTERFACE="$(ip link show | awk -F': ' '/^[0-9]+: / && !/lo/ {print $2; exit}')"
CFG_KEYMAP="fr"
CFG_LANGUAGE="fr"
CFG_ROOT_PASSWORD=""
CFG_USER=""
CFG_USER_PASSWORD=""


# # Configuration des utilisateurs supplémentaires
# export CFG_ADDITIONAL_USERS="${CFG_ADDITIONAL_USERS:-}"
# # Configuration des groupes
# export CFG_ADDITIONAL_GROUPS="${CFG_ADDITIONAL_GROUPS:-users, wheel}"
# # Choix de l'environnement de bureau par défaut
# export CFG_DESKTOP_ENV="${CFG_DESKTOP_ENV:-none}"
# # Choix du gestionnaire de fenêtres par défaut
# export CFG_WINDOW_MANAGER="${CFG_WINDOW_MANAGER:-i3}"
# # Configuration de la gestion des paquets (portage ou autre)
# export CFG_PACKAGE_MANAGER="${CFG_PACKAGE_MANAGER:-portage}"
# # Autres options de configuration
# export CFG_ENABLE_SSH="${CFG_ENABLE_SSH:-y}"
# export CFG_ENABLE_FIREWALL="${CFG_ENABLE_FIREWALL:-y}"


