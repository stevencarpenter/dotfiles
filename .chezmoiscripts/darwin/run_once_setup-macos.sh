#!/usr/bin/env bash
# macOS setup script - runs once after initial chezmoi apply
set -euo pipefail

echo "Running macOS setup..."

# Run brew health checks
brew bundle check --verbose || true
brew doctor || true

# Install rustup if not present
if ! command -v rustup &> /dev/null; then
    echo "Installing rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi

echo "macOS setup completed."
