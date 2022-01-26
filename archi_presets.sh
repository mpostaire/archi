#!/bin/bash

set -eu
shopt -s extglob

# TODO comment explaining how to add presets

# shellcheck disable=SC2034
presets=(
    gnome
)

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

# first argument is the prompt, second argument is the newline ('\n') separated choices
# returns result in 'ret' variable
choose() {
    mapfile -t choices < <(echo -e "$2")
    to_show=$(echo -e "$2" | nl -s ') ')

    [ ${#choices[@]} -eq 0 ] && return 1
    [ ${#choices[@]} -eq 1 ] && ret=${choices[0]} && return

    while true; do
        printf "%s (leave blank for '%s'):\n%s\n> " "$1" "${choices[0]}" "$to_show"
        read_input -e

        case $ret in
            "" ) ret=${choices[0]}; return;;
            +([0-9]) )
                ret=$((ret -= 1))
                if ((ret >= 0 && ret < ${#choices[@]})); then
                    ret=${choices[$ret]}
                    return
                fi;;
            * )
                for elem in "${choices[@]}"; do
                    if [ "$elem" = "$ret" ]; then
                        return
                    fi
                done;;
        esac
        printf "Invalid input\n\n"
    done
}

# TODO
# restore dotfiles here
# restore here gnome config (put in dotfiles?)
# restore gnome extensions here (put in dotfiles?)
# if corectrl command exists, restore here corectrl config (put in dotfiles?) + do this: https://gitlab.com/corectrl/corectrl/-/wikis/Setup
# run 'hp-setup -i' here if hplip was selected for installation (if hp-setup command exists)

gnome_install() {
    pkgs+=(
        gnome
        cups
        unrar
        vim
        firefox
        transmission-gtk
        rhythmbox
        thunderbird
        steam
        mpv
        libreoffice
        keepassxc
        gparted
        ttf-dejavu
        noto-fonts-cjk
        neofetch
        ghex
        gnome-software-packagekit-plugin
        bat
        fzf
        chafa
        youtube-dl
        wget
        chrome-gnome-shell
        megasync-bin
        nautilus-megasync
        rhythmbox-plugin-alternative-toolbar
        ttf-ms-fonts
        visual-studio-code-bin
        nautilus-admin-git
    )

    services+=(
        cups.socket
        gdm.service
    )

    printf "Installing 'yay' (AUR helper)\n"
    sudo pacman -S --needed git base-devel
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -csi
    cd ..

    if [ "$(systemd-detect-virt --vm)" = "none" ]; then
        choose "Select the video driver to install" "xf86-video-amdgpu\nxf86-video-ati\nxf86-video-intel\nnvidia"
        case $ret in
            xf86-video-amdgpu )
                pkgs+=("$ret" vulkan-radeon)
                printf "Install 'corectrl' (AMD GPU OC utility)? [Y/n]:\n> "
                read_input -e
                case $ret in
                    n|N ) ;;
                    * ) pkgs+=(corectrl);;
                esac;;
        esac
        pkgs+=("$ret")
    fi

    printf "\nInstall 'hplip' (HP DeskJet, OfficeJet, Photosmart, Business Inkjet and some LaserJet driver)? [Y/n]:\n> "
    read_input -e
    case $ret in
        y|Y ) pkgs+=(hplip);;
        n|N ) return;;
    esac

    printf "\nInstalling and updating packages\n"
    yay -Syu "${pkgs[@]}"

    printf "\nEnabling services\n"
    for elem in "${services[@]}"; do
        systemctl enable "$elem"
    done
}
