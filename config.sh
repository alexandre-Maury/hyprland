#!/bin/bash

# script config.sh

# Liste des programmes requis pour l'installation
packages=("git" "tar" "links" "curl" "wget")

# DISK=$(lsblk -dno NAME,TYPE | awk '$2 == "disk"' | head -n 1)

# Détection automatique du périphérique de bloc (premier disque trouvé)
export CFG_BLOCK_DEVICE="${CFG_BLOCK_DEVICE:-$(lsblk -nd -o NAME | head -n 1 | sed 's/^/\/dev\//')}"
# Préfixe pour les partitions
export CFG_PART_PREFIX="${CFG_PART_PREFIX:-}"
# Définition du chemin de la partition
export CFG_BLOCK_PART="${CFG_BLOCK_DEVICE}${CFG_PART_PREFIX}"

# Configuration de la partition UEFI par défaut
export CFG_PART_UEFI="${CFG_PART_UEFI:-y}"

# Taille des partitions par défaut (en Mo)
export CFG_PART_BOOT_SIZE="${CFG_PART_BOOT_SIZE:-256}"
export CFG_PART_SWAP_SIZE="${CFG_PART_SWAP_SIZE:-4096}"
export CFG_PART_ROOT_SIZE="${CFG_PART_ROOT_SIZE:-100%}"

# Configuration de LLVM et musl (par défaut non activés)
export CFG_LLVM="${CFG_LLVM:-n}"
export CFG_MUSL="${CFG_MUSL:-n}"

# Fuseau horaire par défaut
export CFG_TIMEZONE="${CFG_TIMEZONE:-Europe/Paris}"

# Configuration des locales
export CFG_LOCALE="${CFG_LOCALE:-fr_FR.UTF-8}"

# Nom d'hôte par défaut
export CFG_HOSTNAME="${CFG_HOSTNAME:-gentoo}"

# Détection automatique de l'interface réseau (première interface trouvée)
export CFG_NETWORK_INTERFACE="${CFG_NETWORK_INTERFACE:-$(ip link show | awk -F': ' '/^[0-9]+: / {print $2}' | head -n 1)}"

# Configuration de la disposition du clavier par défaut
export CFG_KEYMAP="${CFG_KEYMAP:-fr}"

# Configuration de la langue par défaut
export CFG_LANGUAGE="${CFG_LANGUAGE:-fr_FR}"

# Configuration du mot de passe root par défaut
export CFG_ROOT_PASSWORD="${CFG_ROOT_PASSWORD:-toor}"

# Utilisateur par défaut
export CFG_USER="${CFG_USER:-user}"

# Mot de passe utilisateur par défaut
export CFG_USER_PASSWORD="${CFG_USER_PASSWORD:-azerty}"



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


