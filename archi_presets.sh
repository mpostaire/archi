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
        gnome-shell-extension-appindicator-git
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
    cd
    rm -rf yay

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
        sudo systemctl enable "$elem"
    done

    printf "\nRestoring dotfiles\n"
    rm -rf dotfiles
    git clone https://github.com/mpostaire/dotfiles.git
    cd dotfiles
    stow zsh misc
    cd
    sudo cp -Tr "$HOME"/.zsh/ /root/.zsh
    sudo cp "$HOME"/.zshrc /root/.zshrc

    printf "\nRestoring gnome config\n"
    # gsettings set org.gnome.desktop.background picture-uri file:///usr/share/backgrounds/gnome/adwaita-timed.xml # use this to set a wallpaper
    gsettings set org.gnome.desktop.interface show-battery-percentage true
    gsettings set org.gnome.desktop.peripherals.keyboard numlock-state true
    gsettings set org.gnome.desktop.peripherals.touchpad natural-scroll false
    gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true
    gsettings set org.gnome.desktop.wm.keybindings switch-applications "['<Super>Tab']"
    gsettings set org.gnome.desktop.wm.keybindings switch-applications-backward "['<Shift><Super>Tab']"
    gsettings set org.gnome.desktop.wm.keybindings switch-windows "['<Alt>Tab']"
    gsettings set org.gnome.desktop.wm.keybindings switch-windows-backward "['<Shift><Alt>Tab']"
    gsettings set org.gnome.eog.ui sidebar false
    gsettings set org.gnome.gnome-system-monitor show-whose-processes all
    gsettings set org.gnome.nautilus.icon-view default-zoom-level standard
    gsettings set org.gnome.nautilus.preferences show-create-link true
    gsettings set org.gnome.rhythmbox.player play-order random-by-age-and-rating
    gsettings set org.gnome.rhythmbox.plugins.alternative_toolbar display-type 1
    gsettings set org.gnome.rhythmbox.plugins active-plugins "['power-manager', 'audiocd', 'notification', 'rb', 'alternative-toolbar', 'daap', 'mtpdevice', 'replaygain', 'android', 'generic-player', 'mmkeys', 'dbus-media-server', 'iradio', 'audioscrobbler', 'mpris', 'artsearch']"
    gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled true
    gsettings set org.gnome.settings-daemon.plugins.color night-light-schedule-automatic false
    gsettings set org.gnome.settings-daemon.plugins.color night-light-schedule-from 20
    gsettings set org.gnome.settings-daemon.plugins.color night-light-schedule-to 20
    gsettings set org.gnome.settings-daemon.plugins.color night-light-temperature 2177
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type nothing
    gsettings set org.gnome.settings-daemon.plugins.power.sleep-inactive-battery-timeout 900
    gsettings set org.gnome.shell enabled-extensions "['appindicatorsupport@rgcjonas.gmail.com']"
    gsettings set org.gnome.shell favorite-apps "['firefox.desktop', 'org.gnome.Nautilus.desktop', 'thunderbird.desktop', 'steam.desktop', 'visual-studio-code.desktop', 'rhythmbox.desktop', 'org.gnome.Calendar.desktop', 'org.gnome.Software.desktop']"
    gsettings set org.gnome.shell.weather automatic-location true
    gsettings set org.gnome.software download-updates true
    gsettings set org.gnome.software download-updates-notify true
    gsettings set org.gnome.system.location enabled true

    # keybindings
    gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/']"
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ binding '<Primary><Alt>t'
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ command 'gnome-terminal'
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ name 'Terminal'
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/ binding '<Primary><Alt>Delete'
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/ command 'gnome-system-monitor'
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/ name 'Moniteur système'
    gsettings set org.gnome.settings-daemon.plugins.media-keys logout []
    gsettings set org.gnome.settings-daemon.plugins.media-keys next "['<Primary>KP_6']"
    gsettings set org.gnome.settings-daemon.plugins.media-keys play "['<Primary>KP_Divide']"
    gsettings set org.gnome.settings-daemon.plugins.media-keys previous "['<Primary>KP_4']"
    gsettings set org.gnome.settings-daemon.plugins.media-keys stop "['<Primary>KP_5']"
    gsettings set org.gnome.settings-daemon.plugins.media-keys volume-mute "['<Primary>KP_Multiply']"
    gsettings set org.gnome.settings-daemon.plugins.media-keys volume-step 2

    # terminal profile
    gsettings set org.gnome.Terminal.Legacy.Settings theme-variant dark
    gsettings set org.gnome.Terminal.Legacy.ProfilesList default 'd16e38e4-e361-47d5-bc6d-81ac2769dd8c'
    gsettings set org.gnome.Terminal.Legacy.ProfilesList list "['d16e38e4-e361-47d5-bc6d-81ac2769dd8c']"
    gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:d16e38e4-e361-47d5-bc6d-81ac2769dd8c/ audible-bell false
    gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:d16e38e4-e361-47d5-bc6d-81ac2769dd8c/ background-color '#282c34'
    gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:d16e38e4-e361-47d5-bc6d-81ac2769dd8c/ bold-color '#ABB2BF'
    gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:d16e38e4-e361-47d5-bc6d-81ac2769dd8c/ bold-is-bright true
    gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:d16e38e4-e361-47d5-bc6d-81ac2769dd8c/ font 'DejaVu Sans Mono 10'
    gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:d16e38e4-e361-47d5-bc6d-81ac2769dd8c/ foreground-color '#abb2bf'
    gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:d16e38e4-e361-47d5-bc6d-81ac2769dd8c/ palette "['rgb(63,68,81)', 'rgb(224,85,97)', 'rgb(140,194,101)', 'rgb(209,143,82)', 'rgb(74,165,240)', 'rgb(193,98,222)', 'rgb(66,179,194)', 'rgb(230,230,230)', 'rgb(79,86,102)', 'rgb(255,97,110)', 'rgb(165,224,117)', 'rgb(240,164,93)', 'rgb(77,196,255)', 'rgb(222,115,255)', 'rgb(76,209,224)', 'rgb(215,218,224)']"
    gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:d16e38e4-e361-47d5-bc6d-81ac2769dd8c/ use-system-font false
    gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:d16e38e4-e361-47d5-bc6d-81ac2769dd8c/ use-theme-colors false
    gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:d16e38e4-e361-47d5-bc6d-81ac2769dd8c/ visible-name 'One Dark'

    # TODO fix default apps (wip)
    # investigate ~/.config/mimeapps.list in both host and vm and https://wiki.archlinux.org/title/XDG_MIME_Applications#mimeapps.list to understand better and maybe have a good default
    # gio mime application/x-shellscript org.gnome.gedit.desktop
    # gio mime application/x-desktop org.gnome.gedit.desktop
    # gio mime text/markdown org.gnome.gedit.desktop
    # gio mime text/plain org.gnome.gedit.desktop

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
        Option "XkbLayout" "%s"\nEndSection' "$kbd" | sudo tee /etc/X11/xorg.conf.d/00-keyboard.conf


    if command -v corectrl &> /dev/null; then
        printf "\nRestoring corectrl config\n"
        # TODO restore profile
        cp /usr/share/applications/org.corectrl.corectrl.desktop "$HOME"/.config/autostart/org.corectrl.corectrl.desktop

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
