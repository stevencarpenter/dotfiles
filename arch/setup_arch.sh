#!/bin/bash

set -ex

# Install everything I need from pacman and their dependencies
sudo pacman -Syu ripgrep neovim tmux less strace

# Make executable and run the script to setup the /etc/zsh/zshenv
chmod +x ~/.dotfiles/scripts/populate_sys_zshenv.sh
bash .dotfiles/scripts/populate_sys_zshenv.sh

#Run unix setup script
chmod +x ~/.dotfiles/scripts/setup_unix.sh
zsh ~/.dotfiles/scripts/setup_unix.sh

#Set caps lock to escape and make hitting both shifts turn on caps lock
setxkbmap -option caps:escape,shift:both_capslock &
