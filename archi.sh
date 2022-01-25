#!/bin/bash

# Thanks to https://github.com/classy-giraffe/easy-arch and https://github.com/helmuthdu/aui/

set -eu
shopt -s extglob

##################################################

# PRESETS

presets=(
    gnome
)

gnome_before_install() {
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
    )

    aur_pkgs+=(
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

    if [ "$hypervisor" = "none" ]; then
        choose "Select the video driver to install" "xf86-video-amdgpu\nxf86-video-ati\nxf86-video-intel\nnvidia"
        case $ret in
            xf86-video-amdgpu )
                pkgs+=(xf86-video-amdgpu vulkan-radeon)
                printf "Install 'corectrl' (AMD GPU OC utility)? [Y/n]:\n> "
                read_input -e
                case $ret in
                    n|N ) ;;
                    * ) aur_pkgs+=(corectrl);;
                esac;;
            xf86-video-ati ) pkgs+=(xf86-video-ati);;
            xf86-video-intel ) pkgs+=(xf86-video-intel);;
            nvidia ) pkgs+=(nvidia);;
        esac
    fi

    printf "Install 'hplip' (HP DeskJet, OfficeJet, Photosmart, Business Inkjet and some LaserJet driver)? [Y/n]:\n> "
    read_input -e
    case $ret in
        y|Y ) pkgs+=(hplip);;
        n|N ) return;;
    esac
}

# gnome_after_install() {
#     # TODO
#     # restore dotfiles here
#     # restore here gnome config (put in dotfiles?)
#     # restore gnome extensions here (put in dotfiles?)
#     # if corectrl command exists, restore here corectrl config (put in dotfiles?) + do this: https://gitlab.com/corectrl/corectrl/-/wikis/Setup
#     # run 'hp-setup -i' here if hplip was selected for installation (if hp-setup command exists)
# }

##################################################

pkgs=(
    base
    base-devel
    linux
    linux-firmware
    linux-headers
    networkmanager
    grub
    reflector
    zsh
    nano
    git
    wpa_supplicant
    os-prober
    dosfstools
)

aur_pkgs=()

services=(
    NetworkManager
    fstrim.timer
    reflector.timer
)

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

show_drives() {
    lsblk -po NAME,RM,SIZE,RO,TYPE,PTTYPE,FSTYPE,MOUNTPOINTS
}

detect_efi() {
    # EFI detection
    if [ -e /sys/firmware/efi/efivars ]; then
        printf "This install script only supports BIOS mode for now.\n"
        exit 1
    fi
}

detect_virt() {
    hypervisor=$(systemd-detect-virt --vm)
    case $hypervisor in
        kvm )
            printf "KVM detected\n"
            pkgs+=(qemu-guest-agent)
            services+=(qemu-guest-agent);;
        vmware )
            printf "VMWare Workstation/ESXi detected\n"
            pkgs+=(open-vm-tools)
            services+=(vmtoolsd vmware-vmblock-fuse);;
        oracle )
            printf "VirtualBox detected\n"
            pkgs+=(virtualbox-guest-utils)
            services+=(vboxservice);;
        microsoft )
            printf "Hyper-V detected\n"
            pkgs+=(hyperv)
            services+=(hv_fcopy_daemon hv_kvp_daemon hv_vss_daemon);;
    esac
}

ask_keyboard_layout() {
    choose "Select the keyboard layout" "fr-latin9\nbe-latin1\nus"
    kbd="$ret"
    loadkeys "$kbd"
}

update_system_clock() {
    timedatectl set-ntp true
}

partition_drives() {
    while true; do
        show_drives
        printf "\nEnter a drive to partition ('/dev/sda' for example) and type 'done' when there is nothing else to do:\n> "
        read_input
        case $ret in
            done ) break;;
            * )
                if ! cfdisk "$ret"; then
                    printf "Invalid input.\n\n"
                fi
                next;;
        esac
    done
}

format_partitions() {
    while true; do
        show_drives
        printf "\nEnter a partition to format ('/dev/sda1' for example) and type 'done' when there is nothing else to do:\n> "
        read_input
        case $ret in
            done ) break;;
            * )
                if ! mkfs.ext4 "$ret"; then
                    printf "Invalid input.\n\n"
                fi
                sleep 1;; # give time for lsblk to show updated fs
        esac
    done
}

mount_filesystems() {
    umount -R /mnt &> /dev/null || true # prevent umount failure to exit this script

    while true; do
        show_drives
        printf "\nEnter the partition to use as root volume ('/dev/sda1' for example):\n> "
        read_input
        if mount "$ret" /mnt; then
            break
        fi
        printf "Invalid input.\n\n"
    done

    next

    while true; do
        show_drives
        printf "\nEnter a mountpoint ('/home' for example) or type 'done' if there is nothing else to do:\n> "
        read_input
        mountpoint=$ret
        case $ret in
            done ) break;;
            /* )
                mkdir -p /mnt"$mountpoint"
                printf "Select the partition to mount for '%s' ('/dev/sda2' for example):\n> " "$mountpoint"
                read_input
                if ! mount "$ret" /mnt"$mountpoint"; then
                    printf "Invalid input.\n\n"
                else
                    printf "\n"
                fi;;
            * ) printf "Invalid input.\n\n";;
        esac
    done
}

ask_grub() {
    choose "Select the drive where GRUB will be installed" "$(lsblk -dpnI 8,255 -o NAME)"
    grub_drive="$ret"

    if [ -f /etc/default/grub ]; then
        /bin/cp /etc/default/grub /tmp/grub
        sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/;' /tmp/grub
        sed -ir 's/GRUB_CMDLINE_LINUX_DEFAULT=".+"/GRUB_CMDLINE_LINUX_DEFAULT=""/' /tmp/grub
        printf "\nEdit GRUB config? [y/N]:\n> "
        read_input -e
        case $ret in
            y|Y ) nano /tmp/grub;;
        esac
    fi
}

setup_swapfile() {
    while true; do
        printf "\nEnter the swapfile size in MiB (0 = no swap):\n> "
        read_input
        case $ret in
            +(0) ) break;;
            +([0-9]) )
                if dd if=/dev/zero of=/mnt/swapfile bs=1M count="$ret" status=progress; then
                    chmod 600 /mnt/swapfile
                    mkswap /mnt/swapfile
                    # TODO swapon??
                    break
                fi;;
            * ) printf "Invalid input\n\n";;
        esac
    done
}

ask_hostname() {
    printf "\nEnter the hostname ('arch-laptop' for example):\n> "
    read_input
    hostname=$ret
}

ask_root_password() {
    while true; do
        printf "\nEnter the root password:\n> "
        read_input -s
        rootpasswd=$ret

        printf "\nEnter the root password again:\n> "
        read_input -s
        if [ "$rootpasswd" = "$ret" ]; then
            printf "\n"
            break;
        else
            printf "The passwords dont match! Try again\n"
        fi
    done
}

ask_username_and_password() {
    printf "\nEnter the new username:\n> "
    read_input
    user=$ret

    while true; do
        printf "\nEnter the password for '%s':\n> " "$user"
        read_input -s
        userpasswd=$ret

        printf "\nEnter the user password for '%s' again:\n> " "$user"
        read_input -s
        if [ "$userpasswd" = "$ret" ]; then
            break
        else
            printf "The passwords dont match! Try again\n"
        fi
    done
}

ask_preset() {
    printf "\n"
    choose "Select a preset to add on top of the basic installation" "$(printf "%s\n" "${presets[@]}")\nnone"
    preset=$ret
}

set_hostname_user_and_passwords() {
    printf "%s" "$hostname" > /mnt/etc/hostname
    printf "127.0.0.1\tlocalhost\n::1\t\tlocalhost\n127.0.1.1\t%s.localdomain\t%s" "$hostname" "$hostname" >> /mnt/etc/hosts
    
    printf "root:%s" "$rootpasswd" | arch-chroot /mnt chpasswd

    arch-chroot /mnt useradd -m -G wheel -s /bin/zsh "$user"
    printf "%s:%s" "$user" "$userpasswd" | arch-chroot /mnt chpasswd
    sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /mnt/etc/sudoers
}

set_shell_timezone_clock_locales() {
    arch-chroot /mnt /bin/bash << EOF

    printf "Setting zsh as the root shell\n"
    chsh -s /bin/zsh &> /dev/null

    printf "Setting up the timezone\n"
    ln -sf "/usr/share/zoneinfo/$(curl -s http://ip-api.com/line?fields=timezone)" /etc/localtime &>/dev/null

    printf "Setting up the clock\n"
    hwclock --systohc

    printf "Generating the locales\n"
    printf "fr_FR.UTF-8 UTF-8\n" > /etc/locale.gen
    locale-gen &> /dev/null
    printf "LANG=fr_FR.UTF-8" > /etc/locale.conf

    printf "Setting up the console keyboard layout\n"
    printf "KEYMAP=%s\n" "$kbd" > /etc/vconsole.conf
EOF
}

install_system() {
    # preset before install callback
    [[ $(type -t "${preset}"_before_install) == "function" ]] && "${preset}"_before_install
    next

    printf "Ranking mirrors\n"
    reflector --save /etc/pacman.d/mirrorlist --protocol https --latest 10 --sort rate

    printf "Installing 'archlinux-keyring' and 'devtools' on the live session\n"
    pacman -Sy --noconfirm archlinux-keyring devtools

    case $(grep vendor_id /proc/cpuinfo) in
        *GenuineIntel* )
            printf "Intel CPU detected\n"
            pkgs+=(intel-ucode);;
        *AuthenticAMD* )
            printf "AMD CPU detected\n"
            pkgs+=(amd-ucode);;
    esac

    printf "Installing packages\n"
    sed -i 's/#\[multilib\]/\[multilib\]/;/\[multilib]/{n;s/#Include/Include/}' /etc/pacman.conf
    while ! pacstrap /mnt "${pkgs[@]}"; do
        printf "\nRetry? [Y/n]\n"
        read_input -e
        case $ret in
            n|N ) return 1;;
        esac
    done

    printf "Updating pacman config\n"
    sed -i 's/#Color/Color/;s/^#ParallelDownloads.*$/ParallelDownloads = 10/;s/#\[multilib\]/\[multilib\]/;/\[multilib]/{n;s/#Include/Include/}' /mnt/etc/pacman.conf

    set_hostname_user_and_passwords
    set_shell_timezone_clock_locales

    # temporarily disable packagekit hook if it exists (prevents failure on package installation while chrooted)
    mv -f /usr/share/libalpm/hooks/*packagekit-refresh.hook /tmp &> /dev/null || true

    printf "Enabling access to the AUR\n"
    git -C /mnt/home/"$user" clone https://aur.archlinux.org/yay.git
    cd /mnt/home/"$user"/yay
    extra-x86_64-build -c
    cd
    rm -rf /mnt/home/"$user"/yay
    printf "Installing AUR packages\n"
    arch-chroot /mnt yay -Sy --noconfirm "${aur_pkgs[*]}"

    # enable back packagekit hook if it exists
    mv -f /tmp/*packagekit-refresh.hook /usr/share/libalpm/hooks &> /dev/null || true

    printf -- "--save /etc/pacman.d/mirrorlist --protocol https --country BE,DE,FR,GB --latest 10 --sort rate" > /mnt/etc/xdg/reflector/reflector.conf
    printf "Enabling services\n"
    for elem in "${services[@]}"; do
        systemctl enable "$elem" --root=/mnt
    done

    printf "Generating fstab\n"
    genfstab -U /mnt >> /mnt/etc/fstab
    printf "\n# swapfile\n/swapfile none swap defaults 0 0\n" >> /mnt/etc/fstab

    # preset after install callback
    [[ $(type -t "${preset}"_after_install) == "function" ]] && "${preset}"_after_install
}

install_grub() {
    printf "Installing GRUB\n"

    # If we didn't find the gub default config earlier, ask to edit here.
    if [ ! -f /tmp/grub ]; then
        sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/;' /mnt/etc/default/grub
        sed -ir 's/GRUB_CMDLINE_LINUX_DEFAULT=".+"/GRUB_CMDLINE_LINUX_DEFAULT=""/' /mnt/etc/default/grub
        printf "\nEdit GRUB config? [y/N]:\n> "
        read_input -e
        case $ret in
            y|Y ) nano /mnt/etc/default/grub;;
        esac
    else
        /bin/cp /tmp/grub /mnt/etc/default/grub
    fi

    arch-chroot /mnt grub-install --target=i386-pc "$grub_drive"
    arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
}

epilogue() {
    printf "Installation completed, you can reboot now\n"
}

##################################################

# PREINSTALL

umount -R /mnt &> /dev/null || true # prevent umount failure to exit this script

detect_efi
detect_virt
next
ask_keyboard_layout
next
update_system_clock
next
partition_drives
next
format_partitions
next
mount_filesystems
next
ask_grub
next
setup_swapfile
next
ask_hostname
ask_root_password
ask_username_and_password
ask_preset

# INSTALL

next
install_system
next
install_grub
next
epilogue
