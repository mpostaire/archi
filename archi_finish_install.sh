#!/bin/bash

set -eu

check_internet() {
    while [ "$(ping -c 1 archlinux.org | grep '0% packet loss' )" = "" ]; do
        choose "No internet connection. Select what you want to do" "retry\nconnect to wifi (nmtui)\nabort"
        case $ret in
            retry ) ;;
            connect* ) nmtui;;
            abort ) exit 1;;
        esac
    done
}

welcome() {
    rm -rf "$HOME"/.zprofile

    preset=$(cat "$HOME"/archi/preset)
    printf "Proceeding installation of the '%s' preset (you may be asked for your password several times)\n\n" "$preset"

    update_pkg_db

    # shellcheck source=archi_presets.sh
    source "$HOME"/archi/archi_presets.sh
    "$preset"_install
}

cleanup() {
    printf "Cleaning up\n"
    rm -rf "$HOME"/archi
    printf "Installation complete, rebooting now\n"
    sleep 1
    sudo reboot
}

# shellcheck source=archi_funcs.sh
source "$HOME"/archi/archi_funcs.sh

next
check_internet
next
welcome
next
cleanup
