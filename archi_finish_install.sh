#!/bin/bash

set -eu

next() {
    clear
    printf "
    _             _     _       _     
   / \   _ __ ___| |__ (_)  ___| |__  
  / _ \ | '__/ __| '_ \| | / __| '_ \ 
 / ___ \| | | (__| | | | |_\__ \ | | |
/_/   \_\_|  \___|_| |_|_(_)___/_| |_|

--------------------------------------

"
}

# arguments: '-s': don't show input (useful for passwords); '-e': allow empty input.
# returns result in 'ret' variable
# TODO add left right arrow support for inputs to move cursor (up/down for history?)
read_input() {
    _secret=0
    _allow_empty=0
    for arg in "$@"; do
        [ "$arg" = "-s" ] && _secret=1
        [ "$arg" = "-e" ] && _allow_empty=1
    done

    while true; do
        if [ $_secret -eq 1 ]; then
            read -rs ret
        else
            read -r ret
        fi
        case $ret in
            "" )
                if [ $_allow_empty -eq 1 ]; then
                    return
                fi;;
            *\ * ) ;;
            * ) return;;
        esac
        printf "Invalid input.\n\n> "
    done
}

welcome() {
    preset=$(cat "$HOME"/archi/preset)
    printf "Proceeding installation of the '%s' preset\n\n" "$preset"

    printf "Installing 'archlinux-keyring'\n"
    pacman -Sy --noconfirm archlinux-keyring

    # shellcheck source=/dev/null
    source "$HOME"/archi/archi_presets.sh
    cd "$HOME"/archi/
    "$preset"_install
    cd
}

cleanup() {
    printf "Cleaning up\n"
    sed -i "/printf 'Installation script not found\n'/d" "$HOME"/.zprofile
    rm -rf "$HOME"/archi
    printf "Installation complete, rebooting now\n"
    sleep 1
    sudo reboot
}

next
welcome
next
cleanup
