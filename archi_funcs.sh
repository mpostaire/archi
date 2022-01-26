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
# returns result in 'ret' variable
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
# returns 'y' or 'n' in 'ret' variable
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

# first argument is the prompt, second argument is the newline ('\n') separated choices
# returns result in 'ret' variable
choose() {
    mapfile -t choices < <(echo -e "$2")
    to_show=$(echo -e "$2" | nl -s ') ')

    [ ${#choices[@]} -eq 0 ] && return 1
    [ ${#choices[@]} -eq 1 ] && ret=${choices[0]} && return

    while true; do
        printf "$1 (leave blank for '%s'):\n%s" "${choices[0]}" "$to_show"
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
