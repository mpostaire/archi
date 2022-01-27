#!/bin/bash

# Add presets in this file by adding its name in the 'presets' array and creating its function.
#   - A preset can't be named 'none' as it is reserved (it will be ignored if added here).
#   - A preset's function must follow this naming rule: ${preset_name}_install
# See archi_funcs.sh for useful helper functions (don't source the file because it is automatically
# done by the installation scripts)

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
        stow
        discord
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

    printf "Installing 'yay' (AUR helper)\n"
    sudo pacman -S --needed --noconfirm git base-devel
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -csi --noconfirm
    cd ..

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

    printf "\nRestoring dotfiles\n"
    git clone https://github.com/mpostaire/dotfiles.git
    cd dotfiles
    stow zsh misc
    cd
    sudo cp -Tr "$HOME"/.zsh/ /root/.zsh
    sudo cp "$HOME"/.zshrc /root/.zshrc

    printf "\nRestoring gnome config and extensions\n"
    # TODO restore gsettings

    printf "Disabling Wayland\n"
    sudo sed -i 's/^#WaylandEnable=.*$/WaylandEnable=false/' /etc/gdm/custom.conf

    printf "Set GDM keyboard layout and enable touchpad tap-to-click\n"
    sudo -u gdm dbus-launch gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click 'true'
    kbd="us"
    case "$(cat /etc/vconsole.conf)" in
        *fr* ) kbd="fr";;
        *be* ) kbd="be";;
        *us* ) kbd="us";;
    esac
    printf 'Section "InputClass"
        Identifier "system-keyboard"
        MatchIsKeyboard "on"
        Option "XkbLayout" "%s"\nEndSection' "$kbd" > /etc/X11/xorg.conf.d/00-keyboard.conf


    if command -v corectrl &> /dev/null; then
        printf "\nRestoring corectrl config\n"
        # TODO restore profile
        cp /usr/share/applications/org.corectrl.corectrl.desktop ~/.config/autostart/org.corectrl.corectrl.desktop

        printf "Adding corectrl polkit rule\n"
        printf 'polkit.addRule(function(action, subject) {
    if ((action.id == "org.corectrl.helper.init" ||
        action.id == "org.corectrl.helperkiller.init") &&
        subject.local == true &&
        subject.active == true &&
        subject.isInGroup("%s")) {
            return polkit.Result.YES;
    }\n});\n' "$USER" | sudo tee /etc/polkit-1/rules.d/90-corectrl.rules

        printf "Unlocking full AMD GPU controls\n"
        sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="[^"]*/& amdgpu.ppfeaturemask=0xffffffff/' /etc/default/grub
        sudo grub-mkconfig -o /boot/grub/grub.cfg
    fi

    if commmand -v hp-setup &> /dev/null; then
        printf "\nInitializing hplip\n"
        hp-setup -i
    fi

    cp /usr/share/applications/megasync.desktop "$HOME"/.config/autostart
}
