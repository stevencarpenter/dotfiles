# Shared static Brewfile (DFM-50). Run it through scripts/brew-sync.sh, which also applies
# Brewfile.<identity>. Every capability is enabled here (tiling, dev, gui, Apple Silicon).
# Versions in section 2 comments were verified with `brew info --json=v2` on 2026-10-11.
# No masApps are declared.

# ---------------------------------------------------------------------------
# Section 1: taps, GUI casks, fonts and the formulae that need per-entry trust
#
# Trust decision: `trusted: true` only on crush, sketchybar, borders and the aerospace cask.
# Section 2 has none.
# ---------------------------------------------------------------------------

# Taps
# Ungated: carries `crush`, declared in brews below.
tap "charmbracelet/tap"
tap "nikitabobko/tap"
tap "FelixKratz/formulae"

# Brews
brew "atuin"
# Shell binaries: home/.config/zsh/.zshrc probes the Homebrew prefix for zsh and
# the completion paths assume it.
brew "zsh"
brew "zsh-completions"
brew "bash"
brew "bash-completion"
brew "watch"
# Git worktree helper.
brew "worktrunk"
brew "herdr"
brew "mole"
# Homebrew 6 requires formula-level trust and a fully qualified tap name.
brew "charmbracelet/tap/crush", trusted: true
# mactop requires Apple Silicon.
brew "mactop"
# Homebrew 6 requires explicit trust for third-party tap code. Trust is scoped to
# these two formulae, not the whole FelixKratz tap. Fully-qualified names are
# required for formula-level `trusted` to take effect in Brewfile evaluation.
brew "felixkratz/formulae/sketchybar", trusted: true
brew "felixkratz/formulae/borders", trusted: true
brew "railway"
# Swift tooling.
brew "swiftlint"
brew "swiftformat"
brew "swift-format"
brew "xcbeautify"

# Casks
# `op`: kept brew to pair its update/signing cadence with the
# 1Password.app GUI cask for consistent biometric/keychain integration.
cask "1password-cli"
cask "ghostty"
cask "raycast"
cask "1password"
cask "bbedit"
cask "obsidian"
cask "orbstack"
cask "codex"
cask "handy"
# Bespoke Powerlevel10k-patched Meslo build.
cask "font-meslo-for-powerlevel10k"
# aerospace is a third-party tap cask. A fresh machine has no trust.json entry for
# it, so the Brewfile declares the trust (full tap name required).
cask "nikitabobko/tap/aerospace", trusted: true
# SketchyBar icon font (requires gui and tiling).
cask "font-sketchybar-app-font"
cask "font-input"
cask "font-intel-one-mono"
cask "font-iosevka"
cask "font-inconsolata-go-nerd-font"

# ---------------------------------------------------------------------------
# Section 2: CLI tools and fonts. 80 entries (70 formulae, 10 font casks).
# Work-only `conftest` is not installed here.
# None of the 10 font casks duplicates a section 1 cask.
# ---------------------------------------------------------------------------
brew "mise"  # 2026.10.7
brew "uv"  # 0.13.0
brew "fzf"  # 0.74.4
brew "lazygit"  # 0.66.0
brew "zoxide"  # 0.10.0
brew "ripgrep"  # 15.2.0
brew "bat"  # 0.26.1
brew "brotli"  # 1.2.0
brew "curl"  # 8.22.0
brew "fd"  # 10.5.0
brew "grex"  # 1.4.6
brew "htop"  # 3.5.3
brew "jq"  # 1.8.2
brew "make"  # 4.4.1
brew "tree"  # 2.3.2
brew "wget"  # 1.25.0
brew "xz"  # 5.8.4
brew "eza"  # 0.23.5
brew "fastfetch"  # 2.69.0
brew "yazi"  # 26.9.1
brew "sevenzip"  # 26.04
brew "resvg"  # 0.48.1
brew "yq"  # 4.54.1
brew "btop"  # 1.4.7
brew "ffmpeg"  # 9.0.2
brew "neovim"  # 0.12.6
brew "cloc"  # 2.10
brew "mosh"  # 1.4.0
brew "cloudflared"  # 2026.10.0
brew "glow"  # 3.0.0
brew "nmap"  # 7.991
brew "poppler"  # 26.10.0
brew "television"  # 0.15.9
brew "typst"  # 0.15.1
brew "yt-dlp"  # 2026.8.19
brew "git"  # 2.56.0
brew "git-extras"  # 7.5.0
brew "git-filter-repo"  # 2.47.0
brew "git-secrets"  # 1.3.0
brew "git-delta"  # 0.20.1
brew "gh"  # 2.102.0
brew "lazydocker"  # 0.25.2
brew "gnu-sed"  # 4.10
brew "shellcheck"  # 0.11.0
brew "tmux"  # 3.8
brew "cmake"  # 4.4.4
brew "ninja"  # 1.13.2
brew "lychee"  # 0.24.2
brew "markdownlint-cli2"  # 0.23.3
brew "semgrep"  # 1.180.0
brew "just"  # 1.58.0
brew "lefthook"  # 2.2.1
brew "gitleaks"  # 8.30.1
brew "actionlint"  # 1.7.12
brew "yamllint"  # 1.38.0
brew "trivy"  # 0.75.0
brew "osv-scanner"  # 2.6.0
brew "trufflehog"  # 3.99.2
brew "checkov"  # 3.3.20
brew "hadolint"  # 2.15.1
brew "nuclei"  # 3.11.1
brew "ffuf"  # 2.3.0
brew "testssl"  # 3.2.4
brew "gosec"  # 2.29.0
brew "cargo-audit"  # 0.22.2
brew "cargo-deny"  # 0.20.2
brew "bandit"  # 1.9.4
brew "pip-audit"  # 2.10.1
brew "python@3.14"  # 3.14.8
brew "age"  # 1.3.2
cask "font-jetbrains-mono"  # 2.304
cask "font-meslo-lg-nerd-font"  # 3.5.1
cask "font-symbols-only-nerd-font"  # 3.5.1
cask "font-jetbrains-mono-nerd-font"  # 3.5.1
cask "font-fira-code"  # 6.2
cask "font-inconsolata"  # latest
cask "font-liberation"  # 2.1.5,7261482
cask "font-dejavu"  # 2.37
cask "font-victor-mono"  # 1.5.6
cask "font-dejavu-sans-mono-nerd-font"  # 3.5.1
# conftest is work-only (identity == "work"); uncomment on a work machine.
# brew "conftest"  # 0.71.1
