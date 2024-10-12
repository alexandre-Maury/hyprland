#!/usr/bin/env bash

# script post_install.sh

set -e  # Quitte immédiatement en cas d'erreur.

##############################################################################
## Setting the timezone                                                    
##############################################################################
log_info "Configuration du fuseau horaire"
echo "${TIMEZONE}" > /etc/timezone
emerge --config sys-libs/timezone-data
log_success "Configuration du fuseau horaire terminée."

##############################################################################
## Setting the timezone                                                    
##############################################################################
log_info "Configuration des locales"
echo "${LOCALE}" >> /etc/locale.gen
locale-gen
    
# create file
echo "LANG=\"${LANG}\"" > /etc/env.d/02locale
echo "LC_COLLATE=\"${LANG}\"" > /etc/env.d/02locale

env-update && source /etc/profile && export PS1="(chroot) ${PS1}"
log_success "Configuration des locales terminée."

##############################################################################
## Generate hostname                                                
##############################################################################
log_info "Génération du hostname"
echo "${HOSTNAME}" > /etc/hostname
log_success "Génération du hostname terminée"