#!/usr/bin/env bash

# script install.sh

set -e  # Quitte immédiatement en cas d'erreur.

# source config.sh # Inclure le fichier de configuration.
source functions.sh  # Charge les fonctions définies dans le fichier fonction.sh.


chmod +x *.sh # Rendre les scripts exécutables.

# S'assurer que les packages requis sont installés
for pkg in "${packages[@]}"; do
    check_and_install "$pkg"
done

disks() {
    log_info "Select installation disk"
    LIST="$(lsblk -d -n | grep -v "loop" | awk '{print $1, $4}' | nl -s") ")"
    echo "${LIST}"
    OPTION=""

    # shellcheck disable=SC2143
    while [[ -z "$(echo "${LIST}" | grep "  ${OPTION})")" ]]; do
        printf "Choose a disk (e.g.: 1): "
        read -r OPTION
    done

    DISK="$(echo "${LIST}" | grep "  ${OPTION})" | awk '{print $2}')"

    log_ok "DONE"
}


# Main function to run all program
main() {
    check_internet
    disks
    # partitioning
    # formatting
    # mounting
    # date_config
    # download_and_configure_stage3
    # make_conf_portage
    # select_mirrors
    # config_ebuild_repo
    # dns_copy
    # mounting_filesystems
    # enter_environment
}

main