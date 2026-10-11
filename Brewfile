# Static Brewfile for the personal MacBook after the nix removal (DFM-50).
# Run it through scripts/brew-sync.sh. Section 1 reproduces modules/darwin/homebrew.nix
# with every capability enabled (caps.tiling, caps.dev, caps.gui, non-work identity,
# Apple Silicon). Section 2 maps modules/home/packages.nix. Versions in section 2
# comments were verified with `brew info --json=v2` on 2026-10-11.
# No masApps are declared.

# ---------------------------------------------------------------------------
# Section 1: modules/darwin/homebrew.nix
# ---------------------------------------------------------------------------

# Taps
# Ungated: carries `crush`, declared in brews below.
tap "charmbracelet/tap"
tap "nikitabobko/tap"
tap "FelixKratz/formulae"

# Brews
# Atuin migrations require a current client; avoid the soaked Nix pin lag.
brew "atuin", trusted: true
# Shell binaries: kept in Homebrew because dot_config/zsh/.zshrc probes
# the Homebrew prefix for zsh and the completion paths assume it.
brew "zsh", trusted: true
brew "zsh-completions", trusted: true
brew "bash", trusted: true
brew "bash-completion", trusted: true
# GNU `watch` (procps) has spotty Darwin packaging in nixpkgs: kept brew.
brew "watch", trusted: true
# Git worktree helper; not confirmed in nixpkgs: kept brew.
brew "worktrunk", trusted: true
# No nixpkgs equivalent; both are homebrew/core formulae.
brew "herdr", trusted: true
brew "mole", trusted: true
# Crush's FSL-1.1 license prevents Hydra caching, requiring local Nix builds.
# Homebrew 6 requires formula-level trust and a fully qualified tap name.
brew "charmbracelet/tap/crush", trusted: true
# mactop requires Apple Silicon.
brew "mactop", trusted: true
# brew services supervises tailscaled; nix-darwin has no services.tailscale.
# Non-work identity only.
brew "tailscale", trusted: true
# Homebrew 6 requires explicit trust for third-party tap code. Trust is scoped to
# these two formulae, not the whole FelixKratz tap. Fully-qualified names are
# required for formula-level `trusted` to take effect in Brewfile evaluation.
# Both are pinned by scripts/brew-sync.sh (`brew pin sketchybar borders`).
brew "felixkratz/formulae/sketchybar", trusted: true
brew "felixkratz/formulae/borders", trusted: true
# Homebrew supplies newer Railway releases than the soaked unstable pin.
# At the 2026-08-07 comparison: Nix 5.27.0, Homebrew 5.31.0.
brew "railway", trusted: true
# Keep Homebrew bottles until `nix build --dry-run` confirms Darwin cache
# coverage; uncached Swift builds can take hours.
brew "swiftlint", trusted: true
brew "swiftformat", trusted: true
brew "swift-format", trusted: true
brew "xcbeautify", trusted: true

# Casks
# `op`: kept brew to pair its update/signing cadence with the
# 1Password.app GUI cask for consistent biometric/keychain integration.
cask "1password-cli", trusted: true
cask "ghostty", trusted: true
cask "raycast", trusted: true
cask "1password", trusted: true
cask "bbedit", trusted: true
cask "obsidian", trusted: true
cask "orbstack", trusted: true
cask "codex", trusted: true
cask "handy", trusted: true
# Bespoke Powerlevel10k-patched Meslo build: not a standard nixpkgs font.
cask "font-meslo-for-powerlevel10k", trusted: true
# aerospace is a third-party tap cask with no nixpkgs equivalent.
cask "nikitabobko/tap/aerospace", trusted: true
# SketchyBar icon font (requires gui and tiling).
cask "font-sketchybar-app-font", trusted: true
# Homebrew supplies fonts without confirmed Nix cache coverage.
cask "font-input", trusted: true
cask "font-intel-one-mono", trusted: true
cask "font-iosevka", trusted: true
cask "font-inconsolata-go-nerd-font", trusted: true

# ---------------------------------------------------------------------------
# from nix packages.nix
# Section 2: modules/home/packages.nix. 81 entries (71 formulae, 10 font casks).
# Dropped (nix-only): nixd, nixfmt, statix. Work-only `conftest` is not installed here.
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
brew "jj"  # 0.46.0
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
