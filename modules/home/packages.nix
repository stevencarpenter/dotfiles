{
  config,
  pkgs,
  lib,
  caps,
  identity,
  ...
}:

# Core CLI tooling + fonts installed declaratively via nixpkgs (home-manager),
# replacing the CLI/font half of the old dot_config/homebrew/Brewfile.tmpl. The
# macOS-native / GUI / shell-binary remainder stays in Homebrew
# (modules/darwin/homebrew.nix). chezmoi is intentionally NOT included — the
# dotfiles are managed by nix now, not chezmoi.
#
# Font note: home-manager on macOS does not populate ~/Library/Fonts the way
# nix-darwin's fonts.packages populates /Library/Fonts. Per the port contract
# fonts live here; if macOS does not discover them after switch, they should be
# lifted to `fonts.packages` in a darwin module. The bespoke / heavy /
# unconfirmed fonts remain Homebrew casks (see homebrew.nix).
{
  home.packages =
    with pkgs;
    [
      # ─── CLI utilities (all machines) ───────────────────────────────────
      bat # syntax-highlighting cat
      brotli
      curl
      fd # fast find
      fzf # fuzzy finder
      grex # regex generator
      htop
      jq
      gnumake # provides `make`
      ripgrep # rg
      tree
      wget
      xz
      eza # modern ls
      fastfetch
      yazi # TUI file manager
      p7zip # 7zz archive preview for yazi
      resvg # SVG preview for yazi
      yq-go # mikefarah yq (matches the brew `yq`, not the python yq)
      zoxide # smart cd
      btop
      ffmpeg
      neovim
      cloc
      mosh # resilient remote shell for headless tmux
      cloudflared # cloudflare tunnel client
      glow # markdown renderer
      nmap
      poppler-utils # pdftotext/pdfimages/… — nixpkgs `poppler` is the library only
      television # fuzzy finder TUI; binary is `tv`
      typst # typesetting system
      yt-dlp

      # ─── Git & version control ──────────────────────────────────────────
      git
      git-extras
      git-filter-repo
      git-secrets
      delta # git-delta
      gh
      jujutsu # `jj`; .config/jj/config.toml is already linked by dotfiles.nix
      lazydocker
      lazygit

      # ─── Development shell tooling ───────────────────────────────────────
      gnused # gnu-sed
      shellcheck
      tmux # binary only; tmux config stays a raw symlinked dotfile
      nixd # Nix LSP, including flake-provided nix-darwin/HM option sets
      nixfmt # formatter used by LazyVim's Nix extra and nixd
      statix # Nix linter used by LazyVim's Nix extra
      cmake
      ninja
      lychee # link checker
      markdownlint-cli2
      semgrep

      # ─── Repo workflow tooling ──────────────────────────────────────────
      # These are not optional conveniences: the documented workflows break
      # without them. `just` drives every recipe in the Justfile AND the
      # side-channel step in bootstrap.sh; `pre-commit` is invoked by
      # CLAUDE.md, `just pre-commit`, and dotfiles-hygiene-ci.yml, and
      # ai-stack.nix even allowlists ~/.cache/pre-commit for the Claude
      # sandbox; `gitleaks` backs the hook in .pre-commit-config.yaml. All of
      # them were undeclared hand-brews until now.
      just
      pre-commit
      gitleaks
      actionlint # lints .github/workflows/
      yamllint

      # ─── Language / secrets / runtime managers ──────────────────────────
      uv # was a brew formula; now nix (also drives the mcp_sync/aws hooks)
      # python314: pin to Python 3.14+ per the vendored tools' requirement. If
      # the pinned nixpkgs lacks `python314`, fall back to `python3`.
      python314
      mise # runtime manager (binary only; mise config stays a raw dotfile)
      age # age encryption CLI (agenix uses its own; this is for manual use)
    ]
    # ─── GUI base fonts (mirror the Brewfile gui gate) ──────────────────────
    ++ lib.optionals caps.gui [
      jetbrains-mono
      nerd-fonts.meslo-lg # font-meslo-lg-nerd-font
      nerd-fonts.symbols-only # font-symbols-only-nerd-font
      nerd-fonts.jetbrains-mono # font-jetbrains-mono-nerd-font
    ]
    # ─── Dev-only CLI tooling (dev gate) ────────────────────────────────────
    # The Swift toolchain quartet (swiftlint / swiftformat / swift-format /
    # xcbeautify) deliberately does NOT live here. Those attrs exist in the
    # locked nixpkgs, but existing is not the same as being in the binary
    # cache: a Swift build on aarch64-darwin can turn a `darwin-rebuild switch`
    # into a multi-hour source compile. They stay dev-gated Homebrew brews for
    # the same reason iosevka stays a cask (see homebrew.nix). Promote one here
    # only after `nix build --dry-run` reports it under "will be fetched".
    ++ lib.optionals caps.dev [
      helix # `hx`
    ]
    # ─── Dev-flavored fonts, high-confidence nixpkgs attrs (dev gate) ───────
    # The uncertain / heavy remainder stays as dev-gated Homebrew casks.
    ++ lib.optionals caps.dev [
      fira-code
      inconsolata
      liberation_ttf # font-liberation
      dejavu_fonts
      victor-mono
      nerd-fonts.dejavu-sans-mono # font-dejavu-sans-mono-nerd-font
    ]
    # ─── Work-only policy tooling ──────────────────────────────────────────
    ++ lib.optionals (identity == "work") [
      conftest
    ];
}
