#!/bin/bash

# Thanks to https://github.com/classy-giraffe/easy-arch and https://github.com/helmuthdu/aui/

set -eu
shopt -s extglob

# TODO add left right arrow support for inputs to move cursor (up/down for history?)
# TODO put the maximum of the user inputs (like hostname, user, passwords, ...) at the beginning

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
    umount -R /mnt &> /dev/null|| true # prevent umount failure to exit this script

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
                    # swapon??
                    break
                fi;;
            * ) printf "Invalid input\n\n";;
        esac
    done
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

ask_hostname() {
    printf "\nEnter the hostname ('arch-laptop' for example):\n> "
    read_input
    hostname=$ret
}

detect_microcode() {
    case $(grep vendor_id /proc/cpuinfo) in
        *GenuineIntel* ) microcode="intel-ucode";;
        *AuthenticAMD* ) microcode="amd-ucode";;
        * ) printf "Error: unsupported CPU\n"; return 1;;
    esac
}

detect_virt() {
    hypervisor=$(systemd-detect-virt --vm)
    case $hypervisor in
        kvm )
            printf "KVM has been detected\n"
            printf "Installing guest tools\n"
            pacstrap /mnt qemu-guest-agent
            printf "Enabling specific services for the guest tools\n"
            systemctl enable qemu-guest-agent --root=/mnt;;
        vmware )
            printf "VMWare Workstation/ESXi has been detected\n"
            printf "Installing guest tools\n"
            pacstrap /mnt open-vm-tools
            printf "Enabling specific services for the guest tools\n"
            systemctl enable vmtoolsd --root=/mnt
            systemctl enable vmware-vmblock-fuse --root=/mnt;;
        oracle )
            printf "VirtualBox has been detected\n"
            printf "Installing guest tools\n"
            pacstrap /mnt virtualbox-guest-utils
            printf "Enabling specific services for the guest tools\n"
            systemctl enable vboxservice --root=/mnt;;
        microsoft )
            printf "Hyper-V has been detected\n"
            printf "Installing guest tools\n"
            pacstrap /mnt hyperv
            printf "Enabling specific services for the guest tools\n"
            systemctl enable hv_fcopy_daemon --root=/mnt
            systemctl enable hv_kvp_daemon --root=/mnt
            systemctl enable hv_vss_daemon --root=/mnt;;
        * ) ;;
    esac
}

install_base() {
    printf "Ranking mirrors\n"
    reflector --save /etc/pacman.d/mirrorlist --protocol https --latest 10 --sort rate

    pacman -Sy --noconfirm archlinux-keyring

    detect_microcode
    detect_virt

    printf "Installing the base system\n"
    sed -i 's/#\[multilib\]/\[multilib\]/;/\[multilib]/{n;s/#Include/Include/}' /etc/pacman.conf
    pacstrap /mnt base base-devel linux linux-firmware linux-headers $microcode networkmanager grub reflector zsh nano git wpa_supplicant os-prober dosfstools

    printf "Enabling base services\n"
    systemctl enable NetworkManager --root=/mnt
    systemctl enable fstrim.timer --root=/mnt
    printf -- "--save /etc/pacman.d/mirrorlist --protocol https --country BE,DE,FR,GB --latest 10 --sort rate" > /mnt/etc/xdg/reflector/reflector.conf
    systemctl enable reflector.timer --root=/mnt

    printf "Generating fstab\n"
    genfstab -U /mnt >> /mnt/etc/fstab
    printf "\n# swapfile\n/swapfile none swap defaults 0 0\n" >> /mnt/etc/fstab

    printf "Updating pacman config\n"
    sed -i 's/#Color/Color/;s/^#ParallelDownloads.*$/ParallelDownloads = 10/;s/#\[multilib\]/\[multilib\]/;/\[multilib]/{n;s/#Include/Include/}' /mnt/etc/pacman.conf
}

install_grub() {
    printf "Installing GRUB\n"
    arch-chroot /mnt grub-install --target=i386-pc "$grub_drive"
    sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /mnt/etc/default/grub
    printf "\nEdit GRUB config? [y/N]:\n> "
    read_input -e
    case $ret in
        y|Y ) nano /mnt/etc/default/grub;;
    esac
    arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
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

set_hostname_user_and_passwords() {
    printf "%s" "$hostname" > /mnt/etc/hostname
    printf "127.0.0.1\tlocalhost\n::1\t\tlocalhost\n127.0.1.1\t%s.localdomain\t%s" "$hostname" "$hostname" >> /mnt/etc/hosts
    
    printf "root:%s" "$rootpasswd" | arch-chroot /mnt chpasswd

    arch-chroot /mnt useradd -m -G wheel -s /bin/zsh "$user"
    printf "%s:%s" "$user" "$userpasswd" | arch-chroot /mnt chpasswd
    sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /mnt/etc/sudoers
}

install_yay() {
    # exec command as user instead of root
    # test changing aui_packages to /tmp
    su - "$user" -c "
    [[ ! -d aui_packages ]] && mkdir aui_packages
    cd aui_packages
    curl -o yay.tar.gz https://aur.archlinux.org/cgit/aur.git/snapshot/yay.tar.gz
    tar zxvf yay.tar.gz
    rm yay.tar.gz
    cd yay
    makepkg -csi --noconfirm"
}

install_preset() {
    printf "Install the Gnome preset? [Y/n]:\n> "
    read_input -e
    case $ret in
        n|N ) return;;
    esac

    vdriver=""
    while [ "$hypervisor" = "none" ]; do
        printf "\nSelect the video driver to install:\n\t1) xf86-video-amdgpu (NEW)\n\t2) xf86-video-ati (OLD)\n\t3) xf86-video-intel\n\t4) nvidia\n\n> "
        read_input
        vdriver=$ret
        case $vdriver in
            1|xf86-video-amdgpu ) vdriver="xf86-video-amdgpu vulkan-radeon"; break;;
            2|xf86-video-ati ) vdriver=xf86-video-ati; break;;
            3|xf86-video-intel ) vdriver=xf86-video-intel; break;;
            4|nvidia ) vdriver=nvidia; break;;
            * ) vdriver=""; printf "Invalid input.\n\n";;
        esac
    done

    printf "Installing the Gnome preset\n"
    # shellcheck disable=SC2086 # because 'vdriver' can be empty and we don't want pacstrap to fail
    pacstrap /mnt $vdriver gnome cups unrar vim firefox transmission-gtk rhythmbox thunderbird steam mpv libreoffice hplip keepassxc gparted ttf-dejavu noto-fonts-cjk neofetch ghex gnome-software-packagekit-plugin bat fzf chafa

    printf "Enabling services for the Gnome preset\n"
    systemctl enable cups.socket --root=/mnt
    systemctl enable gdm.service --root=/mnt

    # restore here gnome config
    # restore gnome extensions here
    # restore here corectrl config
    # init here hplip
    # install youtube-dl with python-pip

    # AUR
    # install_yay

    # arch-chroot -u maxime /mnt /bin/bash << EOF
    # printf "Enabling access to the AUR\n"
    # pacman --noconfirm -S go
    # pacman -D --asdeps go
    # git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si && cd .. && rm -rf yay

    # printf "Installing the AUR packages"
    # yay -S --noconfirm chrome-gnome-shell megasync-bin nautilus-megasync rhythmbox-plugin-alternative-toolbar ttf-ms-fonts visual-studio-code-bin nautilus-admin-git corectrl
# EOF
}

epilogue() {
    printf "TODO end\n"
    exit # exit the chroot
}

aur_package_install() {
	su - "$user" -c "sudo -v"
	#install package from aur
	for PKG in $1; do
		if ! is_package_installed "${PKG}"; then
			if [[ $AUTOMATIC_MODE -eq 1 ]]; then
				ncecho " ${BBlue}[${Reset}${Bold}X${BBlue}]${Reset} Installing ${AUR} ${Bold}${PKG}${Reset} "
				su - "${username}" -c "${AUR_PKG_MANAGER} --noconfirm -S ${PKG}" >>"$LOG" 2>&1 &
				pid=$!
				progress $pid
			else
				su - "${username}" -c "${AUR_PKG_MANAGER} --noconfirm -S ${PKG}"
			fi
		else
			if [[ $VERBOSE_MODE -eq 0 ]]; then
				cecho " ${BBlue}[${Reset}${Bold}X${BBlue}]${Reset} Installing ${AUR} ${Bold}${PKG}${Reset} success"
			else
				echo -e "Warning: ${PKG} is up to date --skipping"
			fi
		fi
	done
}

##################################################

# PREINSTALL

detect_efi
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

# INSTALL

next
install_base
next
install_grub
set_shell_timezone_clock_locales
set_hostname_user_and_passwords
next
install_preset
next
epilogue
