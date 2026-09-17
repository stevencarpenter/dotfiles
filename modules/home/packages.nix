{
  config,
  pkgs,
  lib,
  caps,
  identity,
  inputs,
  ...
}:

# Nix CLI packages and fonts. macOS-native tools and GUI apps use Homebrew.
# Home-manager does not populate ~/Library/Fonts; nix-darwin's fonts.packages
# populates /Library/Fonts. Remaining font casks live in homebrew.nix.

let
  # Select unstable packages individually so stable transitive dependencies
  # retain their binary-cache hits. Move entries out of stablePackages when
  # adding them here; the assertion rejects duplicates.
  fastMovingPackages = [
    "mise" # runtime manager; its config stays a raw symlinked dotfile
    "uv" # also drives the mcpSync activation hook in sync-hooks.nix
    "fzf"
    "lazygit"
    "zoxide"
    "ripgrep" # binary is `rg`
    # 26.05 (f6107e54, 2026-08-28) ships statix-0-unstable-2026-05-14 whose
    # checkPhase fails on Darwin: cargo insta snapshot collapsible_let_in
    # against the channel rustc. Unstable has 0.5.8-unstable-2026-07-17,
    # hydra-cached. Drop when 26.05 builds pkgs.statix unmodified
    # (NixOS/nixpkgs#524695 is on master; not backported as of this pin).
    "statix" # Nix linter used by LazyVim's Nix extra and flake checks
  ];

  # Use the independent unstable pin; this repo needs no nixpkgs config overrides.
  pkgsFresh = import inputs.nixpkgs-unstable { system = pkgs.stdenv.hostPlatform.system; };

  freshPackages = map (name: pkgsFresh.${name}) fastMovingPackages;

  stablePackages = with pkgs; [
    # ─── CLI utilities (all machines) ───────────────────────────────────
    bat # syntax-highlighting cat
    brotli
    curl
    fd # fast find
    grex # regex generator
    htop
    jq
    gnumake # provides `make`
    tree
    wget
    xz
    eza # modern ls
    fastfetch
    yazi # TUI file manager
    p7zip # 7zz archive preview for yazi
    resvg # SVG preview for yazi
    yq-go # mikefarah yq (matches the brew `yq`, not the python yq)
    btop
    ffmpeg
    neovim
    cloc
    mosh # resilient remote shell for headless tmux
    cloudflared # cloudflare tunnel client
    glow # markdown renderer
    nmap
    poppler-utils # pdftotext/pdfimages/…: nixpkgs `poppler` is the library only
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

    # ─── Development shell tooling ───────────────────────────────────────
    gnused # gnu-sed
    shellcheck
    tmux # binary only; tmux config stays a raw symlinked dotfile
    nixd # Nix LSP, including flake-provided nix-darwin/HM option sets
    nixfmt # formatter used by LazyVim's Nix extra and nixd
    cmake
    ninja
    lychee # link checker
    markdownlint-cli2
    semgrep

    # ─── Repo workflow tooling ──────────────────────────────────────────
    # just runs deployment recipes; lefthook and gitleaks enforce repository hooks.
    just
    lefthook
    gitleaks
    actionlint # lints .github/workflows/
    yamllint

    # ─── Security tooling (SAST / DAST / supply chain) ───────────────────
    # Security agents use these tools; vulnerability databases update at runtime.
    # ZAP runs from its official Docker image through OrbStack.
    trivy # deps + IaC + container images
    osv-scanner # cross-ecosystem lockfile audit
    trufflehog # verified secrets in git history
    checkov # Terraform policy baseline
    hadolint # Dockerfile lint
    nuclei # template-driven DAST
    ffuf # web content discovery
    testssl # TLS config; binary is `testssl.sh`
    gosec # Go SAST
    cargo-audit # RustSec advisories against Cargo.lock
    cargo-deny # Rust dep/licence bans
    bandit # Python SAST
    pip-audit # Python dep audit

    # ─── Language / secrets / runtime managers ──────────────────────────
    # Must match sync-hooks.nix and the vendored tools' Python >= 3.14 requirement.
    python314
    age # age encryption CLI, for manual use (no age secrets are declared here)
  ];

  # GUI fonts.
  guiFonts = lib.optionals caps.gui (
    with pkgs;
    [
      jetbrains-mono
      nerd-fonts.meslo-lg # font-meslo-lg-nerd-font
      nerd-fonts.symbols-only # font-symbols-only-nerd-font
      nerd-fonts.jetbrains-mono # font-jetbrains-mono-nerd-font
    ]
  );
  # Development fonts; remaining casks live in homebrew.nix.
  devFonts = lib.optionals caps.dev (
    with pkgs;
    [
      fira-code
      inconsolata
      liberation_ttf # font-liberation
      dejavu_fonts
      victor-mono
      nerd-fonts.dejavu-sans-mono # font-dejavu-sans-mono-nerd-font
    ]
  );

  # ─── Work-only policy tooling ──────────────────────────────────────────
  workTools = lib.optionals (identity == "work") (
    with pkgs;
    [
      conftest
    ]
  );

  allStable = stablePackages ++ guiFonts ++ devFonts ++ workTools;

  # Check active capability blocks too; all-host flake checks cover other gates.
  # Some font derivations omit pname.
  duplicated = builtins.filter (
    name: builtins.any (p: (p.pname or "") == name) allStable
  ) fastMovingPackages;
in
{
  # Reject duplicate packages before they cause activation file collisions.
  assertions = [
    {
      assertion = duplicated == [ ];
      message =
        "modules/home/packages.nix: "
        + lib.concatStringsSep ", " duplicated
        + " declared in BOTH fastMovingPackages and the stable package list. "
        + "Each package must come from exactly one channel: delete the stable "
        + "entry.";
    }
  ];

  home.packages = allStable ++ freshPackages;
}
