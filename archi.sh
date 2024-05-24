#!/bin/bash

# Thanks to https://github.com/classy-giraffe/easy-arch and https://github.com/helmuthdu/aui/

set -eu
shopt -s extglob

pkgs=(
    base
    base-devel
    linux
    linux-firmware
    linux-headers
    networkmanager
    memtest86+-efi
    reflector
    zsh
    nano
    git
    wpa_supplicant
    os-prober
    dosfstools
    pacman-contrib
    man-pages
    man-db
)

services=(
    NetworkManager
    fstrim.timer
    reflector.timer
)

show_drives() {
    lsblk -pno NAME,RM,SIZE,RO,TYPE,PTTYPE,FSTYPE,PARTTYPENAME,MOUNTPOINTS
}

detect_efi() {
    # EFI detection
    if [ ! -e /sys/firmware/efi/efivars ]; then
        printf "This install script only supports EFI mode.\n"
        exit 1
    fi
}

download_scripts() {
    printf "\nDownloading scripts\n"
    curl -LJO "https://raw.githubusercontent.com/mpostaire/archi/master/{archi_presets,archi_finish_install,archi_funcs}.sh"
    source ./archi_funcs.sh
}

detect_virt() {
    hypervisor=$(systemd-detect-virt --vm) || true
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

wipe_ptables() {
    while true; do
        show_drives
        read_input "\nEnter a drive to wipe its partition tables ('/dev/sda' for example) and type 'done' when there is nothing else to do:"
        case $ret in
            done ) break;;
            * )
                if ! wipefs -a -f "$ret"; then
                    printf "Invalid input.\n\n"
                fi
                next;;
        esac
    done
}

get_efi_part() {
    mapfile -t tmp < <(lsblk -pno NAME --filter 'PARTTYPENAME == "EFI System"')
    ret=${tmp:-}
    if [ -n "${ret}" ]; then
        ret="${ret[0]}"
    fi
}

partition_drives() {
    get_efi_part

    if [ -n "$ret" ]; then
        printf "\nDetected EFI partition: %s\n" "$ret"
    else
        while true; do
            show_drives
            read_input "\nEnter a drive to create a EFI partition ('/dev/sda' for example):"
            case $ret in
                * )
                    sgdisk "$ret" -n 1::+512MiB -t 1:ef00
                    sleep 1 # give time for lsblk to show updated fs
                    get_efi_part
                    mkfs.fat -F 32 "$ret"
                    next
                    break;;
            esac
        done
    fi

    while true; do
        show_drives
        read_input "\nEnter a drive to partition ('/dev/sda' for example) and type 'done' when there is nothing else to do:"
        case $ret in
            done ) break;;
            * )
                if ! cgdisk "$ret"; then
                    printf "Invalid input.\n\n"
                fi
                next;;
        esac
    done
}

format_partitions() {
    while true; do
        show_drives
        read_input "\nEnter a partition to format ('/dev/sda1' for example) and type 'done' when there is nothing else to do:"
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
    while true; do
        show_drives
        read_input "\nEnter the partition to use as root volume ('/dev/sda1' for example):"
        if mount "$ret" /mnt; then
            root_partition="$ret"
            break
        fi
        printf "Invalid input.\n\n"
    done

    get_efi_part
    mkdir -p /mnt/boot
    mount "$ret" /mnt/boot

    next

    while true; do
        show_drives
        read_input "\nEnter a mountpoint ('/home' for example) or type 'done' if there is nothing else to do:"
        mountpoint=$ret
        case $ret in
            done ) break;;
            /* )
                mkdir -p /mnt"$mountpoint"
                read_input "Select the partition to mount for '$mountpoint' ('/dev/sda2' for example):"
                if ! mount "$ret" /mnt"$mountpoint"; then
                    printf "Invalid input.\n\n"
                else
                    printf "\n"
                fi;;
            * ) printf "Invalid input.\n\n";;
        esac
    done
}

setup_swapfile() {
    while true; do
        read_input "\nEnter the swapfile size in MiB (0 = disable swap):"
        case $ret in
            +(0) ) return;;
            +([0-9]) )
                if dd if=/dev/zero of=/mnt/swapfile bs=1M count="$ret" status=progress; then
                    chmod 600 /mnt/swapfile
                    mkswap /mnt/swapfile
                    return
                fi;;
            * ) printf "Invalid input\n\n";;
        esac
    done
}

ask_hostname() {
    read_input "\nEnter the hostname ('arch-laptop' for example):"
    hostname=$ret
}

ask_root_password() {
    while true; do
        read_input -s "\nEnter the root password:"
        rootpasswd=$ret

        read_input -s "\nEnter the root password again:"
        if [ "$rootpasswd" = "$ret" ]; then
            printf "\n"
            break;
        else
            printf "The passwords dont match! Try again\n"
        fi
    done
}

ask_username_and_password() {
    read_input "\nEnter the new username:"
    user=$ret

    while true; do
        read_input -s "\nEnter the password for '$user':"
        userpasswd=$ret

        read_input -s "\nEnter the user password for '$user' again:"
        if [ "$userpasswd" = "$ret" ]; then
            break
        else
            printf "The passwords dont match! Try again\n"
        fi
    done
}

ask_preset() {
    # shellcheck source=archi_presets.sh
    source ./archi_presets.sh
    printf "\n"

    # filter out 'none' if it exists
    presets_aux=()
    # shellcheck disable=SC2154
    for elem in "${presets[@]}"; do
        [ "$elem" != "none" ] && presets_aux+=("$elem")
    done

    choose "Select a preset to add on top of the basic installation" "$(printf "%s\n" "${presets_aux[@]}")\nnone"
    preset=$ret
}

set_hostname_user_and_passwords() {
    printf "%s" "$hostname" > /mnt/etc/hostname
    printf "127.0.0.1\tlocalhost\n::1\t\tlocalhost\n127.0.1.1\t%s.localdomain\t%s" "$hostname" "$hostname" >> /mnt/etc/hosts
    
    printf "root:%s" "$rootpasswd" | arch-chroot /mnt chpasswd

    arch-chroot /mnt useradd -m -G wheel -s /bin/zsh "$user"
    printf "%s:%s" "$user" "$userpasswd" | arch-chroot /mnt chpasswd
    sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /mnt/etc/sudoers
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
    printf "fr_FR.UTF-8 UTF-8\nen_US.UTF-8 UTF-8\n" > /etc/locale.gen
    locale-gen &> /dev/null
    printf "LANG=fr_FR.UTF-8" > /etc/locale.conf

    printf "Setting up the console keyboard layout\n"
    printf "KEYMAP=%s\n" "$kbd" > /etc/vconsole.conf
EOF
}

install_system() {
    printf "Ranking mirrors\n"
    reflector --save /etc/pacman.d/mirrorlist --protocol https --latest 10 --sort rate

    case $(grep vendor_id /proc/cpuinfo) in
        *GenuineIntel* )
            printf "Intel CPU detected\n"
            pkgs+=(intel-ucode);;
        *AuthenticAMD* )
            printf "AMD CPU detected\n"
            pkgs+=(amd-ucode);;
    esac

    update_pkg_db

    printf "Installing packages\n"
    sed -i 's/#Color/Color/;s/^#ParallelDownloads.*$/ParallelDownloads = 5/;s/#\[multilib\]/\[multilib\]/;/\[multilib]/{n;s/#Include/Include/}' /etc/pacman.conf
    while ! pacstrap /mnt "${pkgs[@]}"; do
        read_input_yn "\nRetry?" "Y/n"
        case $ret in
            n ) return 1;;
        esac
    done

    printf "Updating pacman config\n"
    sed -i 's/#Color/Color/;s/^#ParallelDownloads.*$/ParallelDownloads = 5/;s/#\[multilib\]/\[multilib\]/;/\[multilib]/{n;s/#Include/Include/}' /mnt/etc/pacman.conf
    printf '[Trigger]\nOperation = Remove\nOperation = Upgrade\nType = Package\nTarget = *\n\n[Action]\nDescription = Removing old cached packages...\nWhen = PostTransaction\nExec = /usr/bin/env bash -c "/usr/bin/paccache -rk2; /usr/bin/paccache -ruk0"' > /mnt/usr/share/libalpm/hooks/clear-cache.hook
    /bin/cp -f /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist

    set_hostname_user_and_passwords
    set_shell_timezone_clock_locales

    printf -- "--save /etc/pacman.d/mirrorlist --protocol https --latest 10 --sort rate" > /mnt/etc/xdg/reflector/reflector.conf

    printf "Generating fstab\n"
    genfstab -U /mnt > /mnt/etc/fstab
    if [ -f /mnt/swapfile ]; then
        printf "\n# swapfile\n/swapfile none swap defaults 0 0\n" >> /mnt/etc/fstab
    fi

    printf "Installing systemd-boot\n"
    bootctl --esp-path=/mnt/boot install
    services+=(systemd-boot-update.service)
    printf "default      @saved
timeout      4
console-mode max
editor       no\n" > /mnt/boot/loader/loader.conf
    printf "title    Arch Linux
linux    /vmlinuz-linux
initrd   /initramfs-linux.img
sort-key 01
options  root=%s rw\n" "$root_partition" > /mnt/boot/loader/entries/00-arch.conf
    printf "title    Memtest86+
sort-key 02
efi      /memtest86+/memtest.efi\n" > /mnt/boot/loader/entries/10-memtest.conf

    printf "Enabling services\n"
    for elem in "${services[@]}"; do
        systemctl enable "$elem" --root=/mnt
    done
}

prepare_first_reboot() {
    [ "$preset" = "none" ] && return

    mkdir -p /mnt/home/"$user"/archi
    printf "%s" "$preset" > /mnt/home/"$user"/archi/preset
    cp archi_presets.sh /mnt/home/"$user"/archi/archi_presets.sh
    cp archi_funcs.sh /mnt/home/"$user"/archi/archi_funcs.sh
    
    script_path=/home/"$user"/archi/archi_finish_install.sh
    cp archi_finish_install.sh /mnt/"$script_path"
    printf "if [ -f %s ]; then\n\tsh %s\nelse\n\tprintf 'Installation script not found\n'\nfi\n" "$script_path" "$script_path" > /mnt/home/"$user"/.zprofile

    arch-chroot /mnt chown -R "$user":"$user" /home/"$user"/archi
    arch-chroot /mnt chown "$user":"$user" /home/"$user"/.zprofile
}

epilogue() {
    if [ "$preset" = "none" ]; then
        choose "Installation completed, you can reboot or stay in the live session and reboot later" "reboot\ncontinue"
    else
        choose "Base installation completed, you can reboot (and continue to the final installation step after login - use the '$user' account not 'root') or stay in the live session and reboot later" "reboot\ncontinue"
    fi

    case $ret in
        reboot ) reboot;;
    esac
}

##################################################

# PREINSTALL

umount -R /mnt &> /dev/null || true # prevent umount failure to exit this script

detect_efi
download_scripts
detect_virt
next
ask_keyboard_layout
next
update_system_clock
next
wipe_ptables
next
partition_drives
next
format_partitions
next
mount_filesystems
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
prepare_first_reboot
next
epilogue
