#!/usr/bin/env zsh

# Install Brewfile contents and make sure things are chyll (with a y)
brew bundle --file=~/.dotfiles/macOS/Brewfile
brew bundle check --verbose
brew doctor

# Run stow to link dotfiles
cd ~/.dotfiles/ || exit
stow -vvv home
cd ~ || exit

#Run unix setup script
chmod +x ~/.dotfiles/scripts/setup_unix.sh
zsh ~/.dotfiles/scripts/setup_unix.sh

# Install rustup
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
