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

# TODO add read_input_yn function to make easy Y/n or y/N prompts

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

