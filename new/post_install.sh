#!/usr/bin/env bash

# script post_install.sh

set -e  # Quitte immédiatement en cas d'erreur.

##############################################################################
## Setting the locale                                                    
##############################################################################
log_prompt "INFO" "Configuration des locales" && echo ""
echo "${LOCALE}" >> /etc/locale.gen
locale-gen
localectl set-locale "${LANG}"
localectl set-keymap "${KEYMAP}"
localectl set-x11-keymap "${KEYMAP}"
log_prompt "SUCCESS" "Terminée"

# XORG OU WAYLAND
# mkdir -p /etc/X11/xorg.conf.d
# echo " Section "InputClass"" >> /etc/X11/xorg.conf.d/00-keyboard.conf
# echo "    Identifier "system-keyboard"" >> /etc/X11/xorg.conf.d/00-keyboard.conf
# echo "    MatchIsKeyboard "on"" >> /etc/X11/xorg.conf.d/00-keyboard.conf
# echo "    Option "XkbLayout" "fr"" >> /etc/X11/xorg.conf.d/00-keyboard.conf
# echo "    Option "XkbModel" "pc105"" >> /etc/X11/xorg.conf.d/00-keyboard.conf
# echo " EndSection" >> /etc/X11/xorg.conf.d/00-keyboard.conf


##############################################################################
## Installation Hyprland                                                  
##############################################################################




