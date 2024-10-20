#!/bin/bash

# script config.sh


# Détection du mode de démarrage (UEFI ou MBR)
if [ -d /sys/firmware/efi ]; then
  MODE="UEFI"
else
  MODE="MBR"
fi

# Comparaison entre Partition Swap et Fichier Swap :
# Critère	    Partition Swap :	                                            Fichier Swap :
# Performance	Généralement plus rapide en raison d'un accès direct.	        Moins rapide, mais souvent suffisant pour la plupart des usages.
# Flexibilité	Taille fixe, nécessite un redimensionnement pour changer.	    Facile à redimensionner en ajoutant ou supprimant des fichiers.
# Simplicité	Nécessite des opérations de partitionnement.	                Plus simple à configurer et à gérer.
# Gestion	    Nécessite des outils de partitionnement pour la création.	    Peut être géré par des commandes simples.

SWAP_FILE="On" 
SWAP_FILE_SIZE="4096"

# Liste des programmes requis pour l'installation
packages=("git" "tar" "curl" "wget")

#Gentoo Base
GENTOO_BASE="https://distfiles.gentoo.org/releases/amd64/autobuilds/20240929T163611Z/stage3-amd64-systemd-20240929T163611Z.tar.xz"
MOUNT_POINT="/mnt/gentoo"


TIMEZONE="Europe/Paris"
LOCALE="fr_FR.UTF-8 UTF-8"
LANG="fr_FR.UTF-8"
HOSTNAME="gentoo-alexandre"
INTERFACE="$(ip link show | awk -F': ' '/^[0-9]+: / && !/lo/ {print $2; exit}')"
KEYMAP="fr"

COMMON_FLAGS="-O2 -pipe -march=native"
CPU_FLAGS=$(grep -m1 "flags" /proc/cpuinfo | cut -d' ' -f2-) # Automatique
MAKEOPTS="-j$(nproc) -l$(nproc)" # Automatique
USE="systemd pam git curl wget tar"
L10N="fr"
INPUT_DEVICES="libinput synaptics keyboard mouse joystick wacom"

USERNAME="alexandre"

PASSWDQC_CONF="/etc/security/passwdqc.conf"
MIN_SIMPLE="4" # Valeurs : disabled : Longueur minimale pour un mot de passe simple, c'est-à-dire uniquement des lettres minuscules (ex. : "abcdef").
MIN_2CLASSES="4" # Longueur minimale pour un mot de passe avec deux classes de caractères, par exemple minuscules + majuscules ou minuscules + chiffres (ex. : "Abcdef" ou "abc123").
MIN_3CLASSES="4" # Longueur minimale pour un mot de passe avec trois classes de caractères, comme minuscules + majuscules + chiffres (ex. : "Abc123").
MIN_4CLASSES="4" # Longueur minimale pour un mot de passe avec quatre classes de caractères, incluant minuscules + majuscules + chiffres + caractères spéciaux (ex. : "Abc123!").
MIN_PHRASE="4" # Longueur minimale pour une phrase de passe, qui est généralement une suite de plusieurs mots ou une longue chaîne de caractères (ex. : "monmotdepassecompliqué").

MIN="$MIN_SIMPLE,$MIN_2CLASSES,$MIN_3CLASSES,$MIN_4CLASSES,$MIN_PHRASE"
MAX="72" # Définit la longueur maximale autorisée pour un mot de passe. Dans cet exemple, un mot de passe ne peut pas dépasser 72 caractères.
PASSPHRASE="3" # Définit la longueur minimale pour une phrase de passe en termes de nombre de mots. Ici, une phrase de passe doit comporter au moins 3 mots distincts pour être considérée comme valide.
MATCH="4" # Ce paramètre détermine la longueur minimale des segments de texte qui doivent correspondre entre deux chaînes pour être considérées comme similaires.
SIMILAR="permit" # Valeurs : permit ou deny : Définit la politique en matière de similitude entre le mot de passe et d'autres informations (par exemple, le nom de l'utilisateur).
RANDOM="47"
ENFORCE="everyone" #  Valeurs : none ou users ou everyone : Ce paramètre applique les règles de complexité définies à tous les utilisateurs.
RETRY="3" # Ce paramètre permet à l'utilisateur de réessayer jusqu'à 3 fois pour entrer un mot de passe conforme si le mot de passe initial proposé est refusé.