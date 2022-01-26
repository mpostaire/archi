#!/bin/bash

# Add presets in this file by adding its name in the 'presets' array and creating its function.
#   - The presets can't have the name 'none' as it is reserved (it will be ignored if added here).
#   - A preset's function must follow this naming rule: ${preset_name}_install
# See archi_funcs.sh for useful helper functions you can use for presets (don't source the file
# because it is automatically done by the installation scripts)

set -eu

# shellcheck disable=SC2034
presets=(
    gnome
)

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
    sudo pacman -S --needed --noconfirm git base-devel
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -csi --noconfirm
    cd ..

    detect_vdriver
    # shellcheck disable=SC2154 # this script is never called directly but sourced in a script containing the necessary functions
    case $ret in
        xf86-video-amdgpu )
            pkgs+=("$ret" vulkan-radeon)
            read_input_yn "\nInstall 'corectrl' (AMD GPU OC utility)?" "Y/n"
            case $ret in
                y ) pkgs+=(corectrl);;
            esac;;
        none ) ;;
        * ) pkgs+=("$ret");;
    esac

    read_input_yn "\nInstall 'hplip' (HP DeskJet, OfficeJet, Photosmart, Business Inkjet and some LaserJet driver)?" "Y/n"
    case $ret in
        y ) pkgs+=(hplip);;
    esac

    printf "\nInstalling and updating packages\n"
    while ! yay -Syu "${pkgs[@]}" --noconfirm; do
        printf 
        read_input_yn "\nRetry?" "Y/n"
        case $ret in
            n ) return 1;;
        esac
    done

    printf "\nEnabling services\n"
    for elem in "${services[@]}"; do
        systemctl enable "$elem"
    done

    # TODO
    # restore dotfiles here
    # restore here gnome config (put in dotfiles?)
    # restore gnome extensions here (put in dotfiles?)
    # if corectrl command exists, restore here corectrl config (put in dotfiles?) + do this: https://gitlab.com/corectrl/corectrl/-/wikis/Setup
    # run 'hp-setup -i' here if hplip was selected for installation (if hp-setup command exists)
    # megasync autostart
}
