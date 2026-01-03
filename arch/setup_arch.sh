#!/bin/bash
# Arch Linux setup script for dotfiles with Chezmoi

set -ex

# Install core packages from pacman
sudo pacman -Syu chezmoi age ripgrep neovim tmux less strace

# Set up age encryption key from backup
# Note: Copy your key from 1Password to ~/.config/chezmoi/key.txt first
if [[ ! -f ~/.config/chezmoi/key.txt ]]; then
    echo "WARNING: Age encryption key not found at ~/.config/chezmoi/key.txt"
    echo "Please copy your key from 1Password before running chezmoi apply"
fi

# Initialize chezmoi if not already done
if [[ ! -d ~/.local/share/chezmoi ]]; then
    chezmoi init git@github.com:stevencarpenter/dotfiles.git
fi

# Apply dotfiles
chezmoi apply

# Set caps lock to escape and make hitting both shifts turn on caps lock
setxkbmap -option caps:escape,shift:both_capslock &

echo "Arch Linux setup complete!"
echo "Restart your shell with: exec zsh"
