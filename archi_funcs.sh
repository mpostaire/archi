#!/bin/bash

set -eu
shopt -s extglob

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
# returns result in the 'ret' variable
read_input() {
    _secret=0
    _allow_empty=0
    _prompt=""
    for arg in "$@"; do
        case $arg in
            -s ) _secret=1;;
            -e ) _allow_empty=1;;
            * ) [ -z "$_prompt" ] && _prompt=$arg || _prompt="$_prompt $arg";;
        esac
    done

    while true; do
        # shellcheck disable=SC2059
        printf "$_prompt\n"
        if [ $_secret -eq 1 ]; then
            read -ersp "> " ret
        else
            read -erp "> " ret
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

# first argument is the prompt, second argument is 'Y/n' (default is yes), 'y/N' (default is no) or 'y/n' (no default)
# returns 'y' or 'n' in the 'ret' variable
read_input_yn() {
    while true; do
        printf "$1 [%s]\n" "$2"
        read -erp "> " ret
        case ${ret,,} in # lowercase ret
            "" )
                case $2 in
                    "Y/n" ) ret=y; return;;
                    "y/N" ) ret=n; return;;
                esac;;
            y|yes ) ret=y return;;
            n|no ) ret=n return;;
        esac
        printf "Invalid input.\n\n"
    done
}

# first argument is the prompt, second argument is the newline ('\n') separated choices, first space ends the
# match area (example format: 'matchable_choice1 non_matchable_suffix1\nmatchable_choice2')
# returns result in the 'ret' variable
choose() {
    mapfile -t choices < <(echo -e "$2")
    to_show=$(echo -e "$2" | nl -s ') ')

    [ ${#choices[@]} -eq 0 ] && return 1
    [ ${#choices[@]} -eq 1 ] && ret=${choices[0]} && return

    while true; do
        printf "$1 (leave blank for '%s'):\n%s" "${choices[0]% *}" "$to_show"
        read_input -e

        case $ret in
            "" ) ret=${choices[0]% *}; return;;
            +([0-9]) )
                ret=$((ret -= 1))
                if ((ret >= 0 && ret < ${#choices[@]})); then
                    ret=${choices[$ret]% *}
                    return
                fi;;
            * )
                for elem in "${choices[@]}"; do
                    if [ "${elem% *}" = "$ret" ]; then
                        ret=${ret% *}
                        return
                    fi
                done;;
        esac
        printf "Invalid input\n\n"
    done
}

# finds (and prompt for choice if necessary) the video driver to install
# returns the video driver package name or 'none' in the 'ret' variable
detect_vdriver() {
	vga=$(lspci | grep VGA | tr "[:upper:]" "[:lower:]")

    if [ "$(systemd-detect-virt --vm)" != "none" ]; then
        ret="none"
	elif [[ $vga == *"nvidia"* || -f /sys/kernel/debug/dri/0/vbios.rom ]]; then
	    printf "Nvidia GPU detected\n"
        ret="nvidia"
	elif [[ $vga == *"advanced micro devices"* || -f /sys/kernel/debug/dri/0/radeon_pm_info || -f /sys/kernel/debug/dri/0/radeon_sa_info ]]; then
	    printf "AMD GPU detected\n"
		choose "Select the video driver to install" "xf86-video-amdgpu (NEW)\nxf86-video-ati (OLD)"
	elif [[ $vga == *"intel corporation"* || -f /sys/kernel/debug/dri/0/i915_capabilities ]]; then
	    printf "Intel GPU detected\n"
        ret="xf86-video-intel" 
	else
		ret="none"
	fi
}
