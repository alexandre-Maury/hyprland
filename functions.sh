#!/usr/bin/env bash

source log_functions.sh  # Charge les fonctions définies dans le fichier fonction.sh.

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

# Check for internet
check_internet() {
    log_info "Check Internet"
	if ! ping -c1 -w1 8.8.8.8 > /dev/null 2>&1; then
        log_error "No Internet Connection"
        log_info "Visit https://wiki.gentoo.org/wiki/Handbook:AMD64/Installation/Networking"
        log_info "Optionally use 'links https://wiki.gentoo.org/wiki/Handbook:AMD64/Installation/Networking'"
        exit 1
    else
        log_ok "Connected to internet"
	fi
}