{
  config,
  pkgs,
  lib,
  caps,
  identity,
  inputs,
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

let
  # ─── Fast-moving packages: a per-package escape from the stable pin ───────
  # nixpkgs is pinned to 26.05 (flake.nix:8). That line backports fixes but not
  # new upstream releases, so a tool shipping every few days drifts arbitrarily
  # far behind while a tool shipping a few times a year stays current.
  # Everything NOT named here stays on the stable pin — including transitive
  # build inputs, which is exactly why this is explicit selection rather than an
  # overlay. An overlay would rewrite pkgs.<name> globally, so any stable
  # package merely *depending* on ripgrep/fzf would rebuild against unstable and
  # lose its binary-cache hit.
  #
  # Measured 2026-07-26, stable 26.05 → upstream latest:
  #   mise     2026.5.12 → 2026.7.13  (~2 months, ~15 releases)
  #   uv       0.11.21   → 0.11.32    (11 patch releases)
  #   fzf      0.72.0    → 0.74.1
  #   lazygit  0.61.1    → 0.63.1
  #   zoxide   0.9.9     → 0.10.0
  #   ripgrep  15.1.0    → 15.2.0
  # For contrast, gh / yazi / neovim / delta / bat / fd / btop were all exactly
  # current on stable and are deliberately NOT listed. The lag is a cadence
  # mismatch in specific tools, not a general property of the channel.
  #
  # To add a tool: append its nixpkgs attr name here AND delete it from the
  # stable list below. The assertion at the bottom fails the build if you forget
  # the second half.
  fastMovingPackages = [
    "mise" # runtime manager; its config stays a raw symlinked dotfile
    "uv" # also drives the mcpSync activation hook in sync-hooks.nix
    "fzf"
    "lazygit"
    "zoxide"
    "ripgrep" # binary is `rg`
  ];

  # A second nixpkgs that deliberately does not follow the stable input. No
  # `config` argument is needed: this repo sets no `nixpkgs.config` anywhere
  # (no allowUnfree, no overlay stack), so the defaults already match.
  pkgsFresh = import inputs.nixpkgs-unstable { inherit (pkgs) system; };

  freshPackages = map (name: pkgsFresh.${name}) fastMovingPackages;

  # Each capability gate gets its own binding rather than being inlined into one
  # `++` chain, so a consumer can inspect the fully assembled stable set instead
  # of just the base list. `with pkgs;` is repeated per binding because the
  # original single `with` covered the whole concatenation expression, which no
  # longer exists as a single expression.
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
    # NOTE: `uv` and `mise` are declared in fastMovingPackages above, not here.
    # python314: pin to Python 3.14+ per the vendored tools' requirement. If
    # the pinned nixpkgs lacks `python314`, fall back to `python3`.
    python314
    age # age encryption CLI (agenix uses its own; this is for manual use)
  ];

  # ─── GUI base fonts (mirror the Brewfile gui gate) ──────────────────────
  guiFonts = lib.optionals caps.gui (
    with pkgs;
    [
      jetbrains-mono
      nerd-fonts.meslo-lg # font-meslo-lg-nerd-font
      nerd-fonts.symbols-only # font-symbols-only-nerd-font
      nerd-fonts.jetbrains-mono # font-jetbrains-mono-nerd-font
    ]
  );

  # ─── Dev-only CLI tooling (dev gate) ────────────────────────────────────
  # The Swift toolchain quartet (swiftlint / swiftformat / swift-format /
  # xcbeautify) deliberately does NOT live here. Those attrs exist in the
  # locked nixpkgs, but existing is not the same as being in the binary
  # cache: a Swift build on aarch64-darwin can turn a `darwin-rebuild switch`
  # into a multi-hour source compile. They stay dev-gated Homebrew brews for
  # the same reason iosevka stays a cask (see homebrew.nix). Promote one here
  # only after `nix build --dry-run` reports it under "will be fetched".
  devTools = lib.optionals caps.dev (
    with pkgs;
    [
      helix # `hx`
    ]
  );

  # ─── Dev-flavored fonts, high-confidence nixpkgs attrs (dev gate) ───────
  # The uncertain / heavy remainder stays as dev-gated Homebrew casks.
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

  # Concatenation order is identical to the original `++` chain — `home.packages`
  # is a list, so reordering would change the derivation even though the set of
  # packages is unchanged.
  allStable = stablePackages ++ guiFonts ++ devTools ++ devFonts ++ workTools;

  # Names claimed by BOTH channels. Inspects the fully assembled stable set, not
  # just the base list, so a future fast-mover added to a capability-gated block
  # cannot slip past the guard. (It only sees the blocks active for the host
  # being evaluated, but `nix flake check --all-systems` covers every host, so a
  # collision hidden behind another machine's caps still fails CI.)
  # `pname or ""` because a few font derivations do not set pname.
  duplicated = builtins.filter (
    name: builtins.any (p: (p.pname or "") == name) allStable
  ) fastMovingPackages;
in
{
  # Without this, declaring a package in both channels surfaces as a
  # home-manager file collision at activation ("collision between ... /bin/rg")
  # — loud, but pointing at the symptom rather than the cause.
  assertions = [
    {
      assertion = duplicated == [ ];
      message =
        "modules/home/packages.nix: "
        + lib.concatStringsSep ", " duplicated
        + " declared in BOTH fastMovingPackages and the stable package list. "
        + "Each package must come from exactly one channel — delete the stable "
        + "entry.";
    }
  ];

  home.packages = allStable ++ freshPackages;
}
