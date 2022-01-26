#!/bin/bash

# Add presets in this file by adding its name in the 'presets' array and creating its function.
#   - The presets can't have the name 'none' as it is reserved (it will be ignored if added here).
#   - A preset's function must follow this naming rule: ${preset_name}_install

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

    # TODO detect gpu and appropriate driver automatically
    if [ "$(systemd-detect-virt --vm)" = "none" ]; then
        choose "Select the video driver to install" "xf86-video-amdgpu\nxf86-video-ati\nxf86-video-intel\nnvidia"
        # shellcheck disable=SC2154 # this script is never called directly but sourced in a script containing the necessary functions
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
    while true; do
        read_input -e
        case $ret in
            y|Y|"" ) pkgs+=(hplip); break;;
            n|N ) break;;
            * ) printf "Invalid input\n\n> ";;
        esac
    done

    printf "\nInstalling and updating packages\n"
    while ! yay -Syu "${pkgs[@]}" --noconfirm; do
        printf "\nRetry? [Y/n]\n"
        read_input -e
        case $ret in
            n|N ) return 1;;
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
