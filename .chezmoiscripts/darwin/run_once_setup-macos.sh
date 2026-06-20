#!/usr/bin/env bash
# macOS setup script - runs once after initial chezmoi apply
set -euo pipefail

echo "Running macOS setup..."

# Run brew health checks using the new global Brewfile location
brew bundle --global check --verbose || true
brew doctor || true

# Assert Xcode CLT headers and license
if ! xcode-select -p &>/dev/null; then
    echo "Installing Xcode Command Line Tools..."
    xcode-select --install
fi
# Accept license non-interactively (no-op if already accepted)
sudo xcodebuild -license accept 2>/dev/null || true

# Install rustup if not present
if ! command -v rustup &> /dev/null; then
    echo "Installing rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi

echo "macOS setup completed."
