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

# first line sets vconsole's color scheme
# second line sets cursor position to (0,0) and clears the screen
custom_issue="\e]P01D2026\e]P84F5666\e]P1E05561\e]P9FF616E\e]P28CC265\e]PAA5E075\e]P3D18F52\e]PBF0A45D\e]P44AA5F0\e]PC4DC4FF\e]P5C162DE\e]PDDE73FF\e]P642B3C2\e]PE4CD1E0\e]P7D7DAE0\e]PFABB2BF
\e[H\e[2J
        \e[1;36m,\e[1;36m                       _     _ _                      \e[1;30m| \e[34m\s \r
       \e[1;36m/#\\\\\\e[1;36m        __ _ _ __ ___| |__ | (_)_ __  _   ___  __    \e[30m|
      \e[1;36m/###\\\\\\e[1;36m      / _\` | '__/ __| '_ \\\\| | | '_ \\\\| | | \\\\ \\\\/ /    \e[30m| \e[32m\t
     \e[1;36m/#####\\\\\\e[1;36m    | (_| | | | (__| | | | | | | | | |_| |>  <     \e[30m| \e[32m\d
    \e[1;36m/##\e[0;36m,-,##\\\\\\e[1;36m    \\\\__,_|_|  \\\\___|_| |_|_|_|_| |_|\\\\__,_/_/\\\\_\\\\    \e[1;30m|
   \e[0;36m/##(   )##\\\\                                                 \e[1;30m| \e[31m\U logged in
  \e[0;36m/#.--   --.#\\\\\\e[1;37m   A simple, elegant gnu/linux distribution.    \e[1;30m|
 \e[0;36m/\`           \`\\\\\\e[0m                                               \e[1;30m| \e[35m\l \e[36mon \e[1;33m\n \e[0m

"

gnome_install() {
    pkgs=(
        gnome
        cups
        unrar
        neovim
        firefox
        bluez-plugins # needed for PS3 Sixaxis controller bluetooth
        bluez-utils # needed for media control from bluetooth headsets
        transmission-gtk
        rhythmbox
        thunderbird
        ttf-ubuntu-font-family
        steam
        mpv
        libreoffice
        bitwarden
        gparted
        ttf-dejavu
        noto-fonts-cjk
        neofetch
        dnsmasq # needed for gnome's wifi access point to work
        ghex
        bat
        gdb
        fzf
        htop
        yt-dlp
        wget
        stow
        kernel-modules-hook
        gamemode
        lib32-gamemode
        chafa
        discord
        gst-plugin-pipewire # needed for gnome's screen capture to work
        pipewire-alsa
        pipewire-pulse
        pipewire-jack
        pipewire-audio
        wireplumber
        power-profiles-daemon # needed for gnome's power profiles to work
        dosfstools
        exfatprogs
        tailscale
        gnome-shell-extension-appindicator
    )

    aur_pkgs=(
        megasync-bin
        nautilus-megasync
        rhythmbox-plugin-alternative-toolbar
        ttf-ms-fonts
        visual-studio-code-bin
        gnome-browser-connector
    )

    flatpak_pkgs=(
        com.github.iwalton3.jellyfin-media-player
    )

    services=(
        cups.socket
        gdm.service
        bluetooth.service
        linux-modules-cleanup.service
        systemd-resolved.service
        tailscaled.service
    )

    detect_vdriver
    # shellcheck disable=SC2154 # this script is never called directly but sourced in a script containing the necessary functions
    case $ret in
        xf86-video-amdgpu )
            pkgs+=("$ret" vulkan-radeon libva-mesa-driver)
            read_input_yn "\nInstall 'corectrl' (AMD GPU OC utility)?" "Y/n"
            case $ret in
                y ) pkgs+=(corectrl);;
            esac;;
        none ) ;;
        * ) pkgs+=("$ret");;
    esac

    local alt_mediakeys=0
    read_input_yn "\nSetup alternative media keybindings (useful if there is no dedicated media keys on the keyboard)?" "Y/n"
    case $ret in
        y ) alt_mediakeys=1;;
    esac

    printf "Installing 'yay' (AUR helper)\n"
    sudo pacman -S --needed --noconfirm git base-devel
    git clone https://aur.archlinux.org/yay.git
    ( cd yay && makepkg -csi --noconfirm )
    rm -rf yay

    printf "\nInstalling and updating packages\n"
    while ! sudo pacman -Syu --noconfirm "${pkgs[@]}"; do
        printf "\nPackages installation failed\n"
        read_input_yn "Retry?" "Y/n"
        case $ret in
            n ) return 1;;
        esac
    done

    printf "\nInstalling AUR packages\n"
    while ! yay -Syu --noconfirm "${aur_pkgs[@]}"; do
        printf "\nAUR packages installation failed\n"
        read_input_yn "Retry?" "Y/n"
        case $ret in
            n ) return 1;;
        esac
    done

    printf "\nInstalling flatpak packages\n"
    while ! flatpak install flathub -y "${flatpak_pkgs[@]}"; do
        printf "\nFlatpak packages installation failed\n"
        read_input_yn "Retry?" "Y/n"
        case $ret in
            n ) return 1;;
        esac
    done

    printf "\nRemoving unwanted packages\n"
    sudo pacman -Rs --noconfirm gnome-music

    printf "\nEnabling services\n"
    for elem in "${services[@]}"; do
        sudo systemctl enable "$elem"
    done

    printf "\nFinishing systemd-resolved setup\n"
    systemctl start systemd-resolved
    sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

    # enables ssh password popup with gnome-keyring
    systemctl --user enable gcr-ssh-agent.socket

    printf "\nInstalling custom /etc/issue\n"
    printf "%s" "${custom_issue}" | sudo tee /etc/issue

    printf "\nRestoring dotfiles\n"
    rm -rf dotfiles .bashrc
    git clone https://github.com/mpostaire/dotfiles.git
    stow --dir=dotfiles shell defaultapps
    sudo cp -Tr "$HOME"/.zsh/ /root/.zsh
    sudo cp "$HOME"/.zshrc /root/.zshrc
    sudo cp "$HOME"/.bashrc /root/.bashrc

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
    gsettings set org.gnome.gnome-system-monitor show-whose-processes all
    gsettings set org.gnome.nautilus.icon-view default-zoom-level small
    gsettings set org.gnome.nautilus.preferences show-create-link true
    gsettings set org.gnome.rhythmbox.player play-order random-by-age-and-rating
    gsettings set org.gnome.rhythmbox.player volume 0.8
    gsettings set org.gnome.rhythmbox.plugins.alternative_toolbar display-type 1
    gsettings set org.gnome.rhythmbox.plugins.alternative_toolbar volume-control true
    gsettings set org.gnome.rhythmbox.plugins active-plugins "['power-manager', 'audiocd', 'notification', 'rb', 'alternative-toolbar', 'daap', 'mtpdevice', 'replaygain', 'android', 'generic-player', 'mmkeys', 'dbus-media-server', 'iradio', 'audioscrobbler', 'mpris', 'artsearch']"
    gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled true
    gsettings set org.gnome.settings-daemon.plugins.color night-light-schedule-automatic false
    gsettings set org.gnome.settings-daemon.plugins.color night-light-schedule-from 20
    gsettings set org.gnome.settings-daemon.plugins.color night-light-schedule-to 20
    gsettings set org.gnome.settings-daemon.plugins.color night-light-temperature 2177
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type nothing
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout 900
    gsettings set org.gnome.shell enabled-extensions "['appindicatorsupport@rgcjonas.gmail.com']"
    gsettings set org.gnome.shell favorite-apps "['firefox.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Software.desktop', 'org.mozilla.Thunderbird.desktop', 'code.desktop', 'org.gnome.Rhythmbox3.desktop', 'steam.desktop', 'org.gnome.Calendar.desktop']"
    gsettings set org.gnome.shell.weather automatic-location true
    gsettings set org.gnome.software download-updates true
    gsettings set org.gnome.software download-updates-notify true
    gsettings set org.gnome.system.location enabled true
    gsettings set org.gnome.TextEditor restore-session false
    gsettings set org.gnome.TextEditor show-line-numbers true
    gsettings set org.gnome.TextEditor indent-style space
    gsettings set org.gnome.TextEditor tab-width 4
    gsettings set org.gnome.Console audible-bell false
    gsettings set org.gnome.Console visual-bell false

    # keybindings
    gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/']"
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ binding '<Primary><Alt>t'
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ command 'kgx'
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ name 'Terminal'
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/ binding '<Primary><Alt>Delete'
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/ command 'gnome-system-monitor'
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/ name 'Moniteur système'
    gsettings set org.gnome.settings-daemon.plugins.media-keys logout "[]"
    if [[ $alt_mediakeys = 1 ]]; then
        gsettings set org.gnome.settings-daemon.plugins.media-keys next "['<Primary>KP_6']"
        gsettings set org.gnome.settings-daemon.plugins.media-keys play "['<Primary>KP_Divide']"
        gsettings set org.gnome.settings-daemon.plugins.media-keys previous "['<Primary>KP_4']"
        gsettings set org.gnome.settings-daemon.plugins.media-keys stop "['<Primary>KP_5']"
        gsettings set org.gnome.settings-daemon.plugins.media-keys volume-mute "['<Primary>KP_Multiply']"
        gsettings set org.gnome.settings-daemon.plugins.media-keys volume-up "['<Primary>KP_Add']"
        gsettings set org.gnome.settings-daemon.plugins.media-keys volume-down "['<Primary>KP_Subtract']"
    fi
    gsettings set org.gnome.settings-daemon.plugins.media-keys volume-step 2

    # fonts
    gsettings set org.gnome.desktop.interface font-name "Ubuntu 11"
    gsettings set org.gnome.desktop.interface document-font-name "Ubuntu 12"
    gsettings set org.gnome.desktop.interface monospace-font-name "Ubuntu Mono 12"
    gsettings set org.gnome.desktop.wm.preferences titlebar-font "Ubuntu Bold 11"

    printf "Set GDM keyboard layout and enable touchpad tap-to-click\n"
    sudo -u gdm dbus-launch gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click 'true'

    if command -v corectrl &> /dev/null; then
        printf "\nRestoring corectrl config\n"
        # TODO restore profile
        mkdir -p "$HOME"/.config/autostart
        cp /usr/share/applications/org.corectrl.CoreCtrl.desktop "$HOME"/.config/autostart/org.corectrl.CoreCtrl.desktop

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
        sudo sed -i '/options *root=/ s/$/ amdgpu.ppfeaturemask=0xffffffff/' /boot/loader/entries/00-arch.conf
    fi

    # autostart MEGA
    mkdir -p "$HOME"/.config/autostart
    cp /usr/share/applications/megasync.desktop "$HOME"/.config/autostart/megasync.desktop

    link_mega_user_dir() {
        dest_path=$(grep XDG_"$1"_DIR "$HOME"/.config/user-dirs.dirs)
        dest_path=${dest_path#*=}
        dest_path="${dest_path%\"}"
        dest_path="${dest_path#\"}"
        mega_path=$(eval printf "%s" "${dest_path/\$HOME/\$HOME\/MEGA}")
        dest_path=$(eval printf "%s" "$dest_path")
        mkdir -p "$mega_path"
        rm -rf "$dest_path"
        ln -Ts "$mega_path" "$dest_path"
    }

    # create "$HOME"/.config/user-dirs.dirs
    xdg-user-dirs-update

    # make xdg's user dirs symlinks pointing to MEGA's dirs
    link_mega_user_dir DOCUMENTS
    link_mega_user_dir MUSIC
    link_mega_user_dir PICTURES
    link_mega_user_dir VIDEOS
    link_mega_user_dir TEMPLATES

    # create development working dir
    mkdir -p "$HOME"/dev 

    # fix blurry gtk4 font rendering (not needed anymore)
    #mkdir -p "$HOME"/.config/gtk-4.0
    #printf "[Settings]\ngtk-hint-font-metrics=true\n" > "$HOME"/.config/gtk-4.0/settings.ini

    # create 'dev' and 'MEGA' bookmarks for nautilus
    mkdir -p "$HOME"/.config/gtk-3.0
    printf "file://%s/dev\nfile://%s/MEGA" "$HOME" "$HOME" >> "$HOME"/.config/gtk-3.0/bookmarks
}
